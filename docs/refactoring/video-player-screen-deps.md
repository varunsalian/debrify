# Video player screen — dependency report

Inventory at `ed728b078` (`lib/screens/video_player_screen.dart`, 18,106 lines, unformatted), produced by an analyzer 14.3.0 member walk (`parseString`; first token after comments/metadata to end). Each phase appends its own inventory below.

## Top-level declarations

| Start | End | Lines | Declaration |
|---|---|---|---|
| 167 | 169 | 3 | class _ManualSourceValidationFailure |
| 171 | 176 | 6 | class _SeasonEpisodeSelection |
| 178 | 200 | 23 | class _SubtitleApplyAttempt |
| 207 | 223 | 17 | class _IptvZapPage |
| 229 | 254 | 26 | class IptvCatchupRequestGate |
| 268 | 454 | 187 | class VideoPlayerScreen |
| 456 | 18044 | 17589 | class _VideoPlayerScreenState |
| 18046 | 18106 | 61 | class _RandomChoiceTile |

## Class members (all classes, in order)

| Start | End | Lines | Kind | Name |
|---|---|---|---|---|
| 168 | 168 | 1 | ctor | `ctor` |
| 172 | 172 | 1 | field | `season` |
| 173 | 173 | 1 | field | `episode` |
| 175 | 175 | 1 | ctor | `ctor` |
| 179 | 179 | 1 | field | `generation` |
| 180 | 180 | 1 | field | `requested` |
| 181 | 181 | 1 | field | `previous` |
| 182 | 182 | 1 | field | `source` |
| 183 | 183 | 1 | field | `previousStremioId` |
| 184 | 184 | 1 | field | `previousExternalPath` |
| 185 | 185 | 1 | field | `failed` |
| 186 | 186 | 1 | field | `handled` |
| 187 | 187 | 1 | field | `successReturned` |
| 188 | 188 | 1 | field | `persisted` |
| 189 | 189 | 1 | field | `persistedAudioId` |
| 190 | 190 | 1 | field | `persistenceDone` |
| 192 | 199 | 8 | ctor | `ctor` |
| 208 | 208 | 1 | field | `channels` |
| 209 | 209 | 1 | field | `offset` |
| 210 | 210 | 1 | field | `total` |
| 211 | 211 | 1 | field | `sourceId` |
| 212 | 212 | 1 | field | `category` |
| 213 | 213 | 1 | field | `categories` |
| 215 | 222 | 8 | ctor | `ctor` |
| 230 | 230 | 1 | field | `_generation` |
| 231 | 231 | 1 | field | `_activeTicket` |
| 233 | 237 | 5 | method | `begin` |
| 239 | 240 | 2 | method | `isCurrent` |
| 242 | 246 | 5 | method | `complete` |
| 248 | 253 | 6 | method | `cancel` |
| 269 | 283 | 15 | static | `readLocalResume` |
| 285 | 285 | 1 | field | `videoUrl` |
| 287 | 289 | 3 | field | `audioUrl` |
| 290 | 290 | 1 | field | `title` |
| 291 | 291 | 1 | field | `subtitle` |
| 292 | 292 | 1 | field | `playlist` |
| 293 | 293 | 1 | field | `startIndex` |
| 294 | 294 | 1 | field | `rdTorrentId` |
| 295 | 295 | 1 | field | `torboxTorrentId` |
| 296 | 296 | 1 | field | `pikpakCollectionId` |
| 298 | 298 | 1 | field | `requestMagicNext` |
| 300 | 300 | 1 | field | `requestNextChannel` |
| 302 | 303 | 2 | field | `requestChannelById` |
| 305 | 305 | 1 | field | `channelDirectory` |
| 307 | 307 | 1 | field | `initialContinuousShuffle` |
| 308 | 308 | 1 | field | `startFromRandom` |
| 309 | 309 | 1 | field | `randomStartMaxPercent` |
| 311 | 311 | 1 | field | `startAtPercent` |
| 313 | 313 | 1 | field | `hideSeekbar` |
| 315 | 315 | 1 | field | `showChannelName` |
| 316 | 316 | 1 | field | `channelName` |
| 317 | 317 | 1 | field | `channelNumber` |
| 319 | 319 | 1 | field | `showVideoTitle` |
| 321 | 321 | 1 | field | `hideOptions` |
| 323 | 323 | 1 | field | `hideBackButton` |
| 325 | 325 | 1 | field | `httpHeaders` |
| 327 | 327 | 1 | field | `disableAutoResume` |
| 329 | 329 | 1 | field | `viewMode` |
| 331 | 331 | 1 | field | `contentImdbId` |
| 332 | 332 | 1 | field | `contentType` |
| 333 | 333 | 1 | field | `contentSeason` |
| 334 | 334 | 1 | field | `contentEpisode` |
| 335 | 335 | 1 | field | `contentTitle` |
| 336 | 336 | 1 | field | `resumePolicy` |
| 338 | 338 | 1 | field | `iptvChannels` |
| 339 | 339 | 1 | field | `iptvStartIndex` |
| 340 | 340 | 1 | field | `iptvCategories` |
| 341 | 341 | 1 | field | `iptvSourceId` |
| 342 | 342 | 1 | field | `iptvSourceName` |
| 343 | 343 | 1 | field | `iptvSelectedCategory` |
| 344 | 344 | 1 | field | `iptvContentType` |
| 345 | 345 | 1 | field | `iptvSources` |
| 346 | 347 | 2 | field | `iptvBrowseProvider` |
| 349 | 349 | 1 | field | `stremioSources` |
| 350 | 350 | 1 | field | `stremioCurrentSourceIndex` |
| 351 | 351 | 1 | field | `resolveStremioSource` |
| 353 | 353 | 1 | field | `resolveSourceToPlaylist` |
| 354 | 354 | 1 | field | `startupFailoverEnabled` |
| 355 | 355 | 1 | field | `startupResolverProvider` |
| 356 | 356 | 1 | field | `onStremioSourceCommitted` |
| 357 | 357 | 1 | field | `onStartupSourcesExhausted` |
| 360 | 360 | 1 | field | `seriesSourceFetcher` |
| 362 | 362 | 1 | field | `stremioTvChannels` |
| 363 | 363 | 1 | field | `stremioTvCurrentChannelId` |
| 364 | 365 | 2 | field | `stremioTvGuideDataProvider` |
| 366 | 367 | 2 | field | `stremioTvChannelSwitchProvider` |
| 368 | 368 | 1 | field | `stremioTvNextProvider` |
| 370 | 370 | 1 | field | `traktScrobble` |
| 372 | 372 | 1 | field | `traktProgressPercent` |
| 375 | 375 | 1 | field | `simklScrobble` |
| 376 | 376 | 1 | field | `simklProgressPercent` |
| 377 | 377 | 1 | field | `mdblistScrobble` |
| 378 | 378 | 1 | field | `mdblistProgressPercent` |
| 380 | 383 | 4 | field | `initialSubtitles` |
| 385 | 450 | 66 | ctor | `ctor` |
| 452 | 453 | 2 | method | `createState` |
| 458 | 460 | 3 | sfield | `_tvReleaseLogChannel` |
| 461 | 463 | 3 | sfield | `_androidPlayerDiagnosticChannel` |
| 465 | 465 | 1 | field | `_player` |
| 469 | 469 | 1 | field | `_playerCreated` |
| 471 | 474 | 4 | field | `_audioEffectSessionId` |
| 475 | 475 | 1 | field | `_videoController` |
| 476 | 477 | 2 | field | `_androidVideoRendererMode` |
| 479 | 482 | 4 | field | `_tvosDecodeRemedy` |
| 484 | 487 | 4 | field | `_tvosForceSoftwareDecode` |
| 488 | 489 | 2 | field | `_contentDisplayMatchMode` |
| 490 | 490 | 1 | field | `_tvosDisplayMatchToken` |
| 491 | 491 | 1 | field | `_tvosDisplayMatchTimer` |
| 492 | 492 | 1 | field | `_lastTvosDisplayMatchSignature` |
| 494 | 496 | 3 | field | `_audioPassthroughEnabled` |
| 497 | 497 | 1 | field | `_systemAudioEffectsEnabled` |
| 498 | 498 | 1 | field | `_appleMultichannelEnabled` |
| 499 | 499 | 1 | field | `_tvosRouteOutputChannels` |
| 500 | 500 | 1 | field | `_tvosForceStereoAudio` |
| 501 | 501 | 1 | field | `_tvosLegacyAudioOutput` |
| 502 | 502 | 1 | field | `_playerInstanceGeneration` |
| 503 | 503 | 1 | field | `_playerPresentationInitialized` |
| 510 | 510 | 1 | field | `_rendererValidatedForSession` |
| 511 | 511 | 1 | field | `_rendererFallbackInProgress` |
| 512 | 512 | 1 | field | `_rendererStartupGuardToken` |
| 513 | 513 | 1 | field | `_rendererStartupValidationGeneration` |
| 514 | 514 | 1 | field | `_activeOpenedMedia` |
| 515 | 515 | 1 | field | `_activeMediaShouldPlay` |
| 516 | 516 | 1 | field | `_activeMediaUserPaused` |
| 517 | 517 | 1 | field | `_random` |
| 518 | 518 | 1 | field | `_cachedSeriesPlaylist` |
| 519 | 519 | 1 | field | `_activePlaylist` |
| 520 | 520 | 1 | field | `_seriesImdbKnownAtLaunch` |
| 521 | 521 | 1 | field | `_episodeMetadataReady` |
| 522 | 522 | 1 | field | `_playerInitializationFuture` |
| 523 | 523 | 1 | field | `_playlistIdentityToken` |
| 524 | 524 | 1 | field | `_controlsVisible` |
| 525 | 526 | 2 | field | `_currentStreamUrl` |
| 529 | 529 | 1 | field | `_singleFileImdbId` |
| 530 | 530 | 1 | field | `_singleFileImdbFetched` |
| 533 | 533 | 1 | field | `_manualContentImdbId` |
| 534 | 534 | 1 | field | `_manualContentType` |
| 535 | 535 | 1 | field | `_manualContentSeason` |
| 536 | 536 | 1 | field | `_manualContentEpisode` |
| 537 | 537 | 1 | field | `_manualSubtitleDisplayLabel` |
| 540 | 540 | 1 | field | `_isPikPakRetrying` |
| 541 | 541 | 1 | field | `_pikPakRetryCount` |
| 542 | 542 | 1 | field | `_pikPakRetryMessage` |
| 543 | 544 | 2 | field | `_pikPakRetryId` |
| 546 | 579 | 34 | method | `_constructPlaylistItemData` |
| 581 | 605 | 25 | get | `_seriesPlaylist` |
| 607 | 607 | 1 | field | `_hideTimer` |
| 613 | 613 | 1 | field | `_tvBarScope` |
| 614 | 614 | 1 | field | `_tvPlayPauseFocus` |
| 615 | 615 | 1 | field | `_tvProgressFocus` |
| 617 | 620 | 4 | field | `_tvRootFocus` |
| 622 | 629 | 8 | get | `_tvNoTimeline` |
| 631 | 634 | 4 | field | `_tvScrubTarget` |
| 636 | 639 | 4 | field | `_tvLastArrowAt` |
| 640 | 640 | 1 | field | `_tvScrubWasPlaying` |
| 641 | 641 | 1 | field | `_tvScrubRepeats` |
| 643 | 646 | 4 | field | `_tvScrubGeneration` |
| 648 | 649 | 2 | field | `_tvScrubStartedAtGeneration` |
| 654 | 654 | 1 | field | `_isSeekingWithSlider` |
| 655 | 655 | 1 | field | `_lastSliderSeekPos` |
| 659 | 659 | 1 | field | `_showDebrifyBanner` |
| 660 | 660 | 1 | field | `_debrifyBannerFloatingMounted` |
| 661 | 661 | 1 | field | `_debrifyBannerTimer` |
| 669 | 669 | 1 | field | `_showIptvZapBanner` |
| 673 | 673 | 1 | field | `_iptvZapFloatingMounted` |
| 674 | 674 | 1 | field | `_iptvZapChannel` |
| 675 | 675 | 1 | field | `_iptvZapEpg` |
| 676 | 676 | 1 | field | `_iptvZapEpgLoading` |
| 680 | 680 | 1 | field | `_iptvZapClock` |
| 681 | 681 | 1 | field | `_iptvZapHideTimer` |
| 682 | 682 | 1 | field | `_iptvZapTicker` |
| 683 | 683 | 1 | field | `_iptvZapEpgTicket` |
| 685 | 685 | 1 | field | `_ripple` |
| 686 | 686 | 1 | field | `_panIgnore` |
| 687 | 687 | 1 | field | `_currentIndex` |
| 688 | 688 | 1 | field | `_lastTapLocal` |
| 689 | 690 | 2 | field | `_isManualEpisodeSelection` |
| 691 | 691 | 1 | field | `_isAutoAdvancing` |
| 692 | 693 | 2 | field | `_allowResumeForManualSelection` |
| 694 | 694 | 1 | field | `_manualSelectionResetTimer` |
| 695 | 695 | 1 | field | `_continuousShuffleEnabled` |
| 696 | 696 | 1 | field | `_shuffleBag` |
| 697 | 697 | 1 | field | `_showShuffle` |
| 698 | 698 | 1 | field | `_showShuffleInProgress` |
| 699 | 699 | 1 | field | `_activeShowShuffleGeneration` |
| 700 | 700 | 1 | field | `_showShuffleGeneration` |
| 701 | 701 | 1 | field | `_episodeNavigationGeneration` |
| 704 | 704 | 1 | field | `_currentChannelName` |
| 705 | 705 | 1 | field | `_currentChannelNumber` |
| 706 | 706 | 1 | field | `_currentChannelId` |
| 709 | 709 | 1 | field | `_showChannelGuide` |
| 710 | 710 | 1 | field | `_showSyncOverlay` |
| 711 | 711 | 1 | field | `_channelEntries` |
| 714 | 714 | 1 | field | `_showIptvChannelSheet` |
| 715 | 715 | 1 | field | `_currentIptvIndex` |
| 717 | 720 | 4 | field | `_iptvDiag` |
| 728 | 729 | 2 | field | `_iptvReconnectText` |
| 731 | 733 | 3 | field | `_backgroundedAt` |
| 735 | 757 | 23 | field | `_iptvLiveRecovery` |
| 759 | 774 | 16 | method | `_iptvRecoveryEligible` |
| 776 | 825 | 50 | method | `_performIptvLiveRetune` |
| 827 | 827 | 1 | field | `_iptvChannelsOverride` |
| 828 | 828 | 1 | field | `_iptvGuideContextOverride` |
| 829 | 829 | 1 | field | `_iptvCatchupRequests` |
| 830 | 830 | 1 | field | `_iptvStartOverActive` |
| 831 | 831 | 1 | field | `_iptvStartOverLoading` |
| 832 | 832 | 1 | field | `_iptvStartOverTimelineRequested` |
| 834 | 837 | 4 | get | `_iptvStartOverTimelineVisible` |
| 839 | 857 | 19 | method | `_toggleIptvStartOverTimeline` |
| 859 | 867 | 9 | get | `_canStartOverCurrentIptv` |
| 869 | 872 | 4 | get | `_iptvLiveEdgeAction` |
| 874 | 895 | 22 | method | `_toggleIptvStartOver` |
| 897 | 969 | 73 | method | `_startIptvProgrammeFromBeginning` |
| 971 | 975 | 5 | get | `_effectiveIptvChannels` |
| 977 | 980 | 4 | get | `_iptvZapBannerOwnsIdentity` |
| 982 | 984 | 3 | field | `_playerGuideStyle` |
| 987 | 987 | 1 | field | `_dockStyle` |
| 988 | 988 | 1 | field | `_dockPalette` |
| 989 | 989 | 1 | field | `_dockSize` |
| 991 | 997 | 7 | field | `_dockExtent` |
| 999 | 1002 | 4 | field | `_infoPanelHeight` |
| 1004 | 1005 | 2 | field | `_dockVolume` |
| 1007 | 1042 | 36 | get | `_infoPanelSignature` |
| 1044 | 1044 | 1 | field | `_lastInfoPanelSignature` |
| 1046 | 1050 | 5 | field | `_infoPanelGeneration` |
| 1052 | 1055 | 4 | field | `_dockGeometryGeneration` |
| 1057 | 1070 | 14 | method | `_dockGeometrySignature` |
| 1072 | 1072 | 1 | field | `_lastDockGeometrySignature` |
| 1074 | 1079 | 6 | method | `didChangeDependencies` |
| 1081 | 1097 | 17 | method | `_refreshDockGeometry` |
| 1099 | 1109 | 11 | get | `_reservedInfoPanelHeight` |
| 1111 | 1112 | 2 | field | `_playerGuideTokens` |
| 1115 | 1117 | 3 | field | `_recordingSupported` |
| 1118 | 1118 | 1 | field | `_isRecording` |
| 1120 | 1121 | 2 | field | `_recordingTempPath` |
| 1123 | 1138 | 16 | field | `_lifecycle` |
| 1140 | 1145 | 6 | field | `_pausedByLifecycle` |
| 1147 | 1151 | 5 | field | `_engineTaskId` |
| 1153 | 1154 | 2 | field | `_engineFlagOn` |
| 1156 | 1157 | 2 | field | `_engineRefreshTicket` |
| 1159 | 1165 | 7 | field | `_recordLogSub` |
| 1166 | 1166 | 1 | field | `_subtitleDiagnosticLogSub` |
| 1167 | 1167 | 1 | field | `_subtitleDiagnosticGeneration` |
| 1168 | 1168 | 1 | field | `_activeSubtitleApplyAttempt` |
| 1169 | 1171 | 3 | field | `_subtitleSelectionCorrection` |
| 1173 | 1185 | 13 | field | `_desktopRecordingRevisionListener` |
| 1187 | 1193 | 7 | field | `_recordingStartGen` |
| 1195 | 1196 | 2 | get | `_canRecord` |
| 1198 | 1202 | 5 | field | `_iptvGuideContextGeneration` |
| 1204 | 1208 | 5 | method | `_persistIptvGuideContext` |
| 1210 | 1224 | 15 | method | `_anchorIptvGuideCategory` |
| 1226 | 1255 | 30 | method | `_applyIptvGuideCategory` |
| 1257 | 1265 | 9 | method | `_cancelPendingIptvCatchup` |
| 1267 | 1270 | 4 | method | `_beginIptvCatchupRequest` |
| 1272 | 1273 | 2 | method | `_isCurrentIptvCatchupRequest` |
| 1276 | 1276 | 1 | field | `_showSourceSheet` |
| 1277 | 1277 | 1 | field | `_currentSourceIndex` |
| 1278 | 1278 | 1 | field | `_serverWatch` |
| 1279 | 1279 | 1 | field | `_openedWatchSource` |
| 1280 | 1280 | 1 | field | `_watchOpenEpoch` |
| 1281 | 1281 | 1 | field | `_pendingSourcePlaylist` |
| 1282 | 1282 | 1 | field | `_sourcePlaylistResolution` |
| 1284 | 1284 | 1 | field | `_stremioSourcesOverride` |
| 1285 | 1285 | 1 | field | `_resolveStremioSourceOverride` |
| 1288 | 1288 | 1 | field | `_augmentedSources` |
| 1293 | 1293 | 1 | field | `_showPlayerMenu` |
| 1294 | 1294 | 1 | field | `_playerMenuInitialSection` |
| 1295 | 1296 | 2 | field | `_playerMenuKey` |
| 1297 | 1297 | 1 | field | `_menuImdbId` |
| 1298 | 1298 | 1 | field | `_menuContentType` |
| 1299 | 1299 | 1 | field | `_menuSeason` |
| 1300 | 1300 | 1 | field | `_menuEpisode` |
| 1301 | 1301 | 1 | field | `_menuCachedSlots` |
| 1302 | 1302 | 1 | field | `_menuCacheKey` |
| 1305 | 1305 | 1 | field | `_showStremioTvGuide` |
| 1306 | 1306 | 1 | field | `_currentStremioTvChannelId` |
| 1307 | 1307 | 1 | field | `_stremioTvChannelsOverride` |
| 1308 | 1308 | 1 | field | `_showStremioTvNextLoading` |
| 1309 | 1309 | 1 | field | `_currentStremioTvContentImdbId` |
| 1310 | 1310 | 1 | field | `_currentStremioTvContentType` |
| 1311 | 1311 | 1 | field | `_currentStremioTvContentSeason` |
| 1312 | 1312 | 1 | field | `_currentStremioTvContentEpisode` |
| 1313 | 1313 | 1 | field | `_currentStremioTvContentTitle` |
| 1315 | 1318 | 4 | get | `_effectiveSources` |
| 1320 | 1322 | 3 | get | `_effectiveResolver` |
| 1324 | 1325 | 2 | get | `_effectiveStremioTvChannels` |
| 1327 | 1328 | 2 | get | `_effectiveContentImdbId` |
| 1329 | 1330 | 2 | get | `_effectiveContentType` |
| 1331 | 1332 | 2 | get | `_effectiveContentSeason` |
| 1333 | 1334 | 2 | get | `_effectiveContentEpisode` |
| 1335 | 1336 | 2 | get | `_effectiveContentTitle` |
| 1338 | 1349 | 12 | get | `_currentSeriesImdbId` |
| 1354 | 1354 | 1 | field | `_skipSegmentSettingsLoaded` |
| 1355 | 1355 | 1 | field | `_skipSegmentsEnabled` |
| 1356 | 1356 | 1 | field | `_skipSegmentProviderId` |
| 1357 | 1357 | 1 | field | `_skipSegmentProvider` |
| 1358 | 1358 | 1 | field | `_skipSegments` |
| 1359 | 1359 | 1 | field | `_loadedSkipSegmentsKey` |
| 1360 | 1360 | 1 | field | `_loadingSkipSegmentsKey` |
| 1361 | 1361 | 1 | field | `_skipSegmentsFetchGeneration` |
| 1362 | 1362 | 1 | field | `_skipSegmentsCache` |
| 1364 | 1373 | 10 | field | `_skipSegmentsMediaReady` |
| 1376 | 1376 | 1 | field | `_subtitleSettings` |
| 1379 | 1379 | 1 | field | `_cachedStremioSubtitles` |
| 1382 | 1382 | 1 | field | `_cachedAddonSlots` |
| 1387 | 1387 | 1 | field | `_injectedSubtitleSlots` |
| 1388 | 1388 | 1 | field | `_cachedSubtitleKey` |
| 1389 | 1390 | 2 | field | `_selectedStremioSubtitleId` |
| 1391 | 1392 | 2 | field | `_embeddedSubtitleApplied` |
| 1393 | 1394 | 2 | field | `_userManuallySelectedSubtitle` |
| 1395 | 1395 | 1 | field | `_trackPreferencesReadyForAddonSubtitles` |
| 1396 | 1396 | 1 | field | `_subtitlePrioritySelectionQueue` |
| 1397 | 1398 | 2 | field | `_addonSubtitleFetchToken` |
| 1402 | 1402 | 1 | field | `_tempSubtitleFiles` |
| 1403 | 1403 | 1 | field | `_activeExternalSubtitlePath` |
| 1404 | 1404 | 1 | field | `_subtitleOnlyForeignAudio` |
| 1405 | 1405 | 1 | field | `_subtitleForcedOnly` |
| 1406 | 1406 | 1 | get | `_hasSubtitlePolicy` |
| 1407 | 1407 | 1 | field | `_subtitlePreferredAudio` |
| 1408 | 1408 | 1 | field | `_subtitleSelectedAudio` |
| 1409 | 1409 | 1 | field | `_subtitleAudioRevision` |
| 1410 | 1410 | 1 | field | `_subtitleAutoSyncEnabled` |
| 1411 | 1411 | 1 | field | `_subtitleAutoSync` |
| 1414 | 1415 | 2 | field | `_autoSyncPill` |
| 1417 | 1417 | 1 | field | `_autoSyncWindowActive` |
| 1418 | 1418 | 1 | field | `_autoSyncPillHold` |
| 1419 | 1419 | 1 | field | `_autoSyncPillPhaseTimer` |
| 1421 | 1421 | 1 | field | `_autoSyncPillLastShown` |
| 1424 | 1424 | 1 | field | `_isReady` |
| 1425 | 1425 | 1 | field | `_startupGateActive` |
| 1430 | 1430 | 1 | field | `_startupGateOverlayHidden` |
| 1434 | 1434 | 1 | field | `_manualSourceGateActive` |
| 1435 | 1438 | 4 | get | `_validationGateActive` |
| 1439 | 1439 | 1 | field | `_startupGateMessage` |
| 1442 | 1442 | 1 | field | `_resumeWriteGuard` |
| 1446 | 1446 | 1 | field | `_resumeSaveLock` |
| 1451 | 1451 | 1 | field | `_resumeVerifyEpoch` |
| 1452 | 1452 | 1 | field | `_stremioTvStartupSeek` |
| 1453 | 1453 | 1 | field | `_stremioTvStartupWatch` |
| 1454 | 1454 | 1 | field | `_isPlaying` |
| 1457 | 1457 | 1 | field | `_isPipActive` |
| 1458 | 1458 | 1 | field | `_position` |
| 1459 | 1459 | 1 | field | `_duration` |
| 1460 | 1461 | 2 | field | `_playbackUiClock` |
| 1462 | 1463 | 2 | field | `_activeSkipSegmentUi` |
| 1464 | 1464 | 1 | field | `_isTransitioning` |
| 1466 | 1471 | 6 | field | `_seriesNextDispatched` |
| 1472 | 1472 | 1 | field | `_currentEpisodeMarkedAsFinished` |
| 1473 | 1473 | 1 | field | `_currentMovieMarkedAsFinished` |
| 1474 | 1474 | 1 | field | `_currentMovieRewatchStarted` |
| 1475 | 1476 | 2 | field | `_movieCompletionThreshold` |
| 1477 | 1478 | 2 | field | `_episodeCompletionThreshold` |
| 1480 | 1480 | 1 | field | `_posSub` |
| 1481 | 1481 | 1 | field | `_durSub` |
| 1482 | 1482 | 1 | field | `_playSub` |
| 1483 | 1483 | 1 | field | `_paramsSub` |
| 1484 | 1484 | 1 | field | `_trackSub` |
| 1485 | 1485 | 1 | field | `_completedSub` |
| 1486 | 1486 | 1 | field | `_bufferingSub` |
| 1487 | 1487 | 1 | field | `_iptvErrorSub` |
| 1488 | 1488 | 1 | field | `_rendererStartupErrorSub` |
| 1490 | 1494 | 5 | field | `_decoderProbeGeneration` |
| 1495 | 1495 | 1 | field | `_decoderProbeToken` |
| 1496 | 1496 | 1 | field | `_decoderProbeParams` |
| 1497 | 1497 | 1 | field | `_decoderProbeTimer` |
| 1498 | 1498 | 1 | field | `_lastDecoderDiagnosticSignature` |
| 1501 | 1501 | 1 | field | `_showBufferingIndicator` |
| 1502 | 1502 | 1 | field | `_bufferingDebounceTimer` |
| 1505 | 1505 | 1 | field | `_mode` |
| 1506 | 1506 | 1 | field | `_gestureStartPosition` |
| 1507 | 1507 | 1 | field | `_gestureStartVideoPosition` |
| 1508 | 1508 | 1 | field | `_gestureStartVolume` |
| 1509 | 1509 | 1 | field | `_gestureStartBrightness` |
| 1512 | 1514 | 3 | field | `_seekHud` |
| 1515 | 1516 | 2 | field | `_verticalHud` |
| 1517 | 1518 | 2 | field | `_aspectRatioHud` |
| 1521 | 1521 | 1 | field | `_aspectMode` |
| 1522 | 1522 | 1 | field | `_playbackSpeed` |
| 1528 | 1528 | 1 | field | `_sleepTimerMode` |
| 1530 | 1533 | 4 | field | `_sleepTimerDeadline` |
| 1535 | 1537 | 3 | field | `_sleepTimerArmedMinutes` |
| 1538 | 1538 | 1 | field | `_sleepTimer` |
| 1540 | 1544 | 5 | field | `_sleepStopLatched` |
| 1547 | 1547 | 1 | field | `_speedBeforeHold` |
| 1548 | 1548 | 1 | field | `_speedHoldHud` |
| 1551 | 1551 | 1 | field | `_landscapeLocked` |
| 1553 | 1562 | 10 | get | `_startsInPortrait` |
| 1565 | 1565 | 1 | field | `_rainbowController` |
| 1566 | 1566 | 1 | field | `_rainbowOpacity` |
| 1567 | 1567 | 1 | field | `_rainbowActive` |
| 1568 | 1568 | 1 | field | `_transitionRunning` |
| 1569 | 1569 | 1 | field | `_transitionStopTimer` |
| 1570 | 1570 | 1 | field | `_transitionPhaseTimer` |
| 1571 | 1571 | 1 | field | `_transitionPhase` |
| 1572 | 1572 | 1 | field | `_transitionPhase2Started` |
| 1575 | 1575 | 1 | field | `_tvStaticMessage` |
| 1576 | 1576 | 1 | field | `_tvStaticSubtext` |
| 1577 | 1586 | 10 | field | `_tvStaticMessages` |
| 1589 | 1589 | 1 | field | `_dynamicTitle` |
| 1592 | 1592 | 1 | field | `_traktScrobbleEnabled` |
| 1595 | 1595 | 1 | field | `_launchTraktPercentSpent` |
| 1598 | 1598 | 1 | field | `_traktEpisodeProgress` |
| 1599 | 1599 | 1 | field | `_traktLastScrobbleAction` |
| 1600 | 1600 | 1 | field | `_traktHeartbeatTimer` |
| 1603 | 1603 | 1 | field | `_simklScrobbleEnabled` |
| 1604 | 1604 | 1 | field | `_launchSimklPercentSpent` |
| 1607 | 1607 | 1 | field | `_simklEpisodeProgress` |
| 1608 | 1608 | 1 | field | `_mdblistEpisodeProgress` |
| 1609 | 1609 | 1 | field | `_episodeTrackerProgressImdbId` |
| 1610 | 1610 | 1 | field | `_launchMdblistPercentSpent` |
| 1611 | 1611 | 1 | field | `_simklLastScrobbleAction` |
| 1612 | 1612 | 1 | field | `_simklHeartbeatTimer` |
| 1613 | 1613 | 1 | field | `_mdblistSession` |
| 1615 | 1615 | 1 | field | `_analyticsHeartbeatTimer` |
| 1617 | 1632 | 16 | method | `_randomStartOffset` |
| 1634 | 1642 | 9 | method | `_percentStartOffset` |
| 1644 | 1795 | 152 | method | `initState` |
| 1797 | 1818 | 22 | method | `_loadSkipSegmentSettings` |
| 1820 | 1831 | 12 | method | `_loadLocalCompletionThresholds` |
| 1833 | 1839 | 7 | get | `_usesLocalCompletionTracking` |
| 1841 | 1841 | 1 | field | `_forceLocalCompletionTracking` |
| 1843 | 1857 | 15 | method | `_loadTrackingPolicy` |
| 1859 | 1863 | 5 | get | `_currentLocalMovieImdbId` |
| 1865 | 1869 | 5 | method | `_resetLocalCompletionState` |
| 1871 | 1935 | 65 | method | `_currentSkipSegmentRequest` |
| 1937 | 1998 | 62 | method | `_syncSkipSegmentsForCurrentContent` |
| 2000 | 2013 | 14 | method | `_resetSkipSegmentState` |
| 2015 | 2019 | 5 | get | `_activeSkipSegment` |
| 2021 | 2023 | 3 | method | `_syncActiveSkipSegmentUi` |
| 2025 | 2039 | 15 | method | `_skipActiveSegment` |
| 2041 | 2057 | 17 | method | `_initTraktScrobble` |
| 2059 | 2081 | 23 | get | `_persistablePosition` |
| 2083 | 2089 | 7 | method | `_traktProgress` |
| 2091 | 2115 | 25 | method | `_traktSeasonEpisode` |
| 2117 | 2165 | 49 | method | `_traktScrobble` |
| 2167 | 2216 | 50 | method | `_startTraktHeartbeat` |
| 2218 | 2221 | 4 | method | `_stopTraktHeartbeat` |
| 2223 | 2236 | 14 | method | `_startAnalyticsHeartbeat` |
| 2238 | 2287 | 50 | method | `_traktScrobbleSeek` |
| 2294 | 2319 | 26 | method | `_initSimklScrobble` |
| 2321 | 2328 | 8 | method | `_simklSeriesSEUnresolved` |
| 2330 | 2368 | 39 | method | `_simklScrobble` |
| 2370 | 2421 | 52 | method | `_startSimklHeartbeat` |
| 2423 | 2426 | 4 | method | `_stopSimklHeartbeat` |
| 2428 | 2469 | 42 | method | `_simklScrobbleSeek` |
| 2471 | 2486 | 16 | method | `_mdblistTarget` |
| 2488 | 2545 | 58 | method | `_initMdblistScrobble` |
| 2547 | 2551 | 5 | method | `_updateMdblistPosition` |
| 2553 | 2557 | 5 | method | `_mdblistPlay` |
| 2559 | 2563 | 5 | method | `_mdblistPause` |
| 2565 | 2579 | 15 | method | `_mdblistStop` |
| 2581 | 2584 | 4 | method | `_mdblistScrobbleSeek` |
| 2586 | 2599 | 14 | method | `_resumeTrackingAfterValidationGate` |
| 2601 | 2609 | 9 | method | `_switchMdblistTarget` |
| 2611 | 2620 | 10 | method | `_bindEpisodeTrackerProgressIdentity` |
| 2622 | 2675 | 54 | method | `_currentEpisodeTraktPercent` |
| 2677 | 2727 | 51 | method | `_currentEpisodeSimklPercent` |
| 2729 | 2748 | 20 | method | `_currentEpisodeMdblistPercent` |
| 2750 | 2761 | 12 | method | `_setExternalAudioTrack` |
| 2763 | 2814 | 52 | method | `_attachAudioEffectSession` |
| 2816 | 2824 | 9 | method | `_releaseAudioEffectSession` |
| 2826 | 2833 | 8 | field | `_outputLease` |
| 2835 | 2857 | 23 | sfield | `_outputLeaseTimeout` |
| 2859 | 2899 | 41 | method | `_claimVideoOutput` |
| 2901 | 2904 | 4 | method | `_releaseVideoOutput` |
| 2906 | 2910 | 5 | field | `_screenDisposed` |
| 2912 | 2938 | 27 | method | `_createPlayerInstance` |
| 2940 | 2971 | 32 | method | `_installSubtitleAutoSyncForPlayer` |
| 2973 | 2978 | 6 | method | `_disposeSubtitleAutoSync` |
| 2980 | 2996 | 17 | method | `_applyAutoSubtitleSyncOffset` |
| 2998 | 3033 | 36 | method | `_showSubtitleAutoSyncNotice` |
| 3035 | 3049 | 15 | method | `_openAutoSyncPillWindow` |
| 3051 | 3061 | 11 | method | `_showAutoSyncPillResult` |
| 3063 | 3070 | 8 | method | `_hideAutoSyncPill` |
| 3072 | 3087 | 16 | method | `_setActiveExternalSubtitlePath` |
| 3089 | 3099 | 11 | method | `_applyAspectVideoZoom` |
| 3101 | 3105 | 5 | field | `_passthroughFlipChain` |
| 3107 | 3121 | 15 | method | `_setAudioPassthroughLive` |
| 3123 | 3153 | 31 | method | `_applyPassthroughFlip` |
| 3155 | 3195 | 41 | method | `_configurePlayerAudio` |
| 3197 | 3223 | 27 | method | `_installTvosDecodeRemedy` |
| 3225 | 3262 | 38 | method | `_onPlayerInstanceReady` |
| 3264 | 3703 | 440 | method | `_initializePlayer` |
| 3705 | 3759 | 55 | method | `_watchStremioTvStartup` |
| 3761 | 3788 | 28 | method | `_reportStartupFailure` |
| 3790 | 4038 | 249 | method | `_bindPlayerInstanceSubscriptions` |
| 4040 | 4072 | 33 | method | `_cancelPlayerInstanceSubscriptions` |
| 4074 | 4074 | 1 | field | `_mediaServerFrameGeneration` |
| 4076 | 4108 | 33 | method | `_handleDecoderProbeParams` |
| 4110 | 4126 | 17 | method | `_resetTvosDisplayMatchForMediaBoundary` |
| 4128 | 4196 | 69 | method | `_scheduleTvosDisplayMatch` |
| 4198 | 4239 | 42 | method | `_installDecoderObservers` |
| 4241 | 4266 | 26 | method | `_scheduleRendererStartupValidation` |
| 4268 | 4311 | 44 | method | `_validateRendererStartup` |
| 4313 | 4330 | 18 | method | `_canFallbackExplicitRenderer` |
| 4332 | 4502 | 171 | method | `_fallbackExplicitRendererToAutomatic` |
| 4504 | 4519 | 16 | method | `_scheduleDecoderProbe` |
| 4521 | 4679 | 159 | method | `_reportActiveVideoDecoder` |
| 4681 | 4691 | 11 | method | `_emitDecoderDiagnosticOnce` |
| 4693 | 4718 | 26 | method | `_beginMediaGeneration` |
| 4720 | 4724 | 5 | field | `_networkTuning` |
| 4726 | 4732 | 7 | field | `_networkTuningDefaults` |
| 4734 | 4739 | 6 | field | `_networkTuningChain` |
| 4741 | 4755 | 15 | method | `_applyNetworkTuning` |
| 4757 | 4792 | 36 | method | `_applyNetworkTuningInner` |
| 4794 | 4946 | 153 | method | `_openMedia` |
| 4948 | 4977 | 30 | method | `_releasePlayerDiagnostic` |
| 4979 | 4999 | 21 | method | `didUpdateWidget` |
| 5002 | 5010 | 9 | method | `_waitForVideoReady` |
| 5014 | 5029 | 16 | method | `_waitForSubtitleTracks` |
| 5031 | 5032 | 2 | static | `_diagnosticSubtitleId` |
| 5034 | 5046 | 13 | method | `_setNativeSubtitleVisibilityForTrack` |
| 5048 | 5108 | 61 | method | `_setSubtitleTrackWithDiagnostics` |
| 5110 | 5184 | 75 | method | `_handleSubtitleApplyFailure` |
| 5186 | 5197 | 12 | method | `_showSubtitleFailureMessage` |
| 5200 | 5208 | 9 | method | `_waitForDuration` |
| 5210 | 5242 | 33 | method | `_getLastPlayedEpisode` |
| 5244 | 5345 | 102 | method | `_onPlaybackEnded` |
| 5347 | 5364 | 18 | method | `_startTransitionOverlay` |
| 5366 | 5367 | 2 | method | `_getCurrentEpisodeTitle` |
| 5369 | 5473 | 105 | method | `_getCurrentEpisodeTitleInfo` |
| 5475 | 5555 | 81 | method | `_getCurrentEpisodeSubtitle` |
| 5557 | 5594 | 38 | method | `_getEnhancedMetadata` |
| 5596 | 5658 | 63 | method | `_findNextEpisodeIndex` |
| 5660 | 5689 | 30 | method | `_getMainGroupIndices` |
| 5691 | 5754 | 64 | method | `_showRandomPlaybackMenu` |
| 5756 | 5779 | 24 | method | `_toggleContinuousShuffle` |
| 5781 | 5802 | 22 | method | `_playRandomOnce` |
| 5804 | 5932 | 129 | method | `_playShowShuffle` |
| 5934 | 5959 | 26 | method | `_shuffleEligibleIndices` |
| 5961 | 5980 | 20 | method | `_pickShuffleIndex` |
| 5982 | 6044 | 63 | method | `_findPreviousEpisodeIndex` |
| 6046 | 6062 | 17 | method | `_hasNextEpisode` |
| 6064 | 6078 | 15 | method | `_hasPreviousEpisode` |
| 6080 | 6083 | 4 | method | `_clearBufferingIndicator` |
| 6085 | 6236 | 152 | method | `_goToNextEpisode` |
| 6238 | 6279 | 42 | method | `_fetchNextEpisodeInPlayer` |
| 6281 | 6359 | 79 | method | `_handleSeriesNextEpisode` |
| 6361 | 6378 | 18 | method | `_parseChannelDirectory` |
| 6380 | 6391 | 12 | method | `_loadSubtitleSettings` |
| 6393 | 6401 | 9 | method | `_dockBand` |
| 6403 | 6429 | 27 | method | `_skipButtonBottom` |
| 6431 | 6450 | 20 | method | `_loadDockPrefs` |
| 6452 | 6519 | 68 | method | `_loadPlayerDefaults` |
| 6521 | 6536 | 16 | method | `_onSubtitleStyleChanged` |
| 6538 | 6543 | 6 | method | `_applySubtitleSyncOffset` |
| 6545 | 6555 | 11 | method | `_resetSubtitleSyncOffset` |
| 6557 | 6564 | 8 | method | `_tvReleaseFocusForOverlay` |
| 6566 | 6572 | 7 | method | `_showSyncOverlayPanel` |
| 6574 | 6576 | 3 | method | `_hideSyncOverlay` |
| 6578 | 6601 | 24 | method | `_buildSyncOverlay` |
| 6603 | 6625 | 23 | method | `_buildSliderSyncOverlay` |
| 6627 | 6638 | 12 | method | `_showChannelGuideOverlay` |
| 6640 | 6645 | 6 | method | `_hideChannelGuideOverlay` |
| 6647 | 6656 | 10 | method | `_showIptvChannelSheetOverlay` |
| 6658 | 6664 | 7 | method | `_hideIptvChannelSheet` |
| 6666 | 6692 | 27 | method | `_switchToIptvGuideChannel` |
| 6694 | 6784 | 91 | method | `_reanchorIptvRingToCategory` |
| 6800 | 6804 | 5 | sfield | `_kIptvZapPageSize` |
| 6806 | 6807 | 2 | sfield | `_kIptvZapEdgeMargin` |
| 6809 | 6811 | 3 | field | `_iptvZapWindowOffset` |
| 6813 | 6815 | 3 | field | `_iptvZapCategoryTotal` |
| 6817 | 6821 | 5 | field | `_iptvZapPagingActive` |
| 6823 | 6828 | 6 | field | `_iptvZapSourceId` |
| 6829 | 6829 | 1 | field | `_iptvZapCategory` |
| 6830 | 6830 | 1 | field | `_iptvZapCategories` |
| 6832 | 6832 | 1 | field | `_iptvZapRequestTicket` |
| 6833 | 6833 | 1 | field | `_iptvZapRequestInFlight` |
| 6835 | 6838 | 4 | field | `_iptvZapPendingInputs` |
| 6839 | 6839 | 1 | field | `_iptvZapDrainingInputs` |
| 6841 | 6843 | 3 | field | `_iptvZapCachedOriginCategory` |
| 6844 | 6844 | 1 | field | `_iptvZapCachedDirection` |
| 6845 | 6845 | 1 | field | `_iptvZapCachedPage` |
| 6847 | 6851 | 5 | get | `_canZapIptvChannel` |
| 6853 | 6857 | 5 | method | `_clearIptvZapBoundaryCache` |
| 6859 | 6872 | 14 | method | `_resetIptvZapPaging` |
| 6874 | 6876 | 3 | field | `_iptvZapArmingPaging` |
| 6878 | 6898 | 21 | method | `_ensureIptvZapPagingArmed` |
| 6900 | 6942 | 43 | method | `_zapIptvChannel` |
| 6944 | 6991 | 48 | method | `_requestIptvZapPage` |
| 6993 | 7026 | 34 | method | `_parseIptvZapPage` |
| 7028 | 7055 | 28 | method | `_installIptvZapWindow` |
| 7057 | 7095 | 39 | method | `_mergeIptvZapPage` |
| 7097 | 7120 | 24 | method | `_prefetchIptvZapPage` |
| 7122 | 7128 | 7 | method | `_adjacentIptvCategory` |
| 7130 | 7172 | 43 | method | `_prefetchAdjacentIptvCategory` |
| 7174 | 7188 | 15 | method | `_consumeCachedAdjacentIptvCategory` |
| 7190 | 7205 | 16 | method | `_enterIptvZapCategory` |
| 7207 | 7256 | 50 | method | `_requestAdjacentIptvCategory` |
| 7258 | 7261 | 4 | method | `_queuePendingIptvZapInput` |
| 7263 | 7279 | 17 | method | `_drainPendingIptvZapInputs` |
| 7281 | 7354 | 74 | method | `_playIptvCatchup` |
| 7356 | 7360 | 5 | field | `_iptvSwitchTicket` |
| 7362 | 7365 | 4 | field | `_iptvChannelKey` |
| 7367 | 7374 | 8 | field | `_iptvErrorsMuted` |
| 7376 | 7380 | 5 | field | `_lastIptvErrorShown` |
| 7382 | 7436 | 55 | method | `_onIptvStreamError` |
| 7438 | 7485 | 48 | method | `_setIptvSources` |
| 7487 | 7504 | 18 | method | `_initIptvStremioSources` |
| 7506 | 7517 | 12 | get | `_currentIptvChannel` |
| 7532 | 7532 | 1 | field | `_lastLiveChannelTimer` |
| 7533 | 7533 | 1 | field | `_lastLiveChannelArmedUrl` |
| 7535 | 7540 | 6 | sfield | `_lastLiveChannelSettle` |
| 7542 | 7579 | 38 | method | `_noteLiveChannelPlaying` |
| 7581 | 7589 | 9 | get | `_hasIptvNext` |
| 7591 | 7592 | 2 | get | `_hasIptvPrevious` |
| 7594 | 7603 | 10 | get | `_isIptvSeriesContext` |
| 7605 | 7608 | 4 | field | `_preferredIptvAudioLanguage` |
| 7610 | 7620 | 11 | method | `_iptvSeriesAudioKey` |
| 7622 | 7643 | 22 | method | `_captureIptvAudioLanguage` |
| 7645 | 7689 | 45 | method | `_applyIptvAudioPreference` |
| 7691 | 7721 | 31 | method | `_recordIptvWatchForChannel` |
| 7723 | 7737 | 15 | method | `_desktopCaptureForCurrent` |
| 7739 | 7911 | 173 | method | `_toggleRecording` |
| 7913 | 7924 | 12 | method | `_playingLiveUrl` |
| 7926 | 7958 | 33 | method | `_engineRecordUrlForCurrent` |
| 7960 | 7992 | 33 | method | `_refreshEngineRecordingState` |
| 7994 | 8010 | 17 | method | `_recordingFileName` |
| 8012 | 8046 | 35 | method | `_currentRecordingResource` |
| 8048 | 8056 | 9 | method | `_tapMpvLogsForRecording` |
| 8058 | 8061 | 4 | method | `_untapMpvLogs` |
| 8063 | 8133 | 71 | method | `_startRecording` |
| 8135 | 8153 | 19 | method | `_disarmStrayRecording` |
| 8155 | 8212 | 58 | method | `_stopRecording` |
| 8214 | 8244 | 31 | method | `_publishRecording` |
| 8246 | 8296 | 51 | method | `_recordingTargetPath` |
| 8298 | 8502 | 205 | method | `_switchToIptvChannel` |
| 8504 | 8561 | 58 | method | `_tryOpenLiveStream` |
| 8563 | 8700 | 138 | method | `_openStartupDebridDirect` |
| 8702 | 8880 | 179 | method | `_tryOpenStartupVod` |
| 8882 | 9151 | 270 | method | `_openInitialVodWithFailover` |
| 9153 | 9173 | 21 | method | `_commitValidatedStremioSource` |
| 9175 | 9184 | 10 | method | `_startupSourceFields` |
| 9186 | 9191 | 6 | method | `_setStartupGateActive` |
| 9193 | 9197 | 5 | method | `_setStartupGateMessage` |
| 9201 | 9209 | 9 | method | `_showSourceSheetOverlay` |
| 9211 | 9216 | 6 | method | `_hideSourceSheet` |
| 9218 | 9238 | 21 | method | `_buildSourceSheetResolver` |
| 9240 | 9265 | 26 | method | `_handleSourceSelected` |
| 9267 | 9322 | 56 | method | `_switchToIptvSource` |
| 9324 | 9623 | 300 | method | `_switchToSourcePlaylist` |
| 9625 | 9625 | 1 | field | `_activeHttpHeaders` |
| 9627 | 9817 | 191 | method | `_switchToStremioSource` |
| 9821 | 9827 | 7 | method | `_findInitialStremioTvChannelId` |
| 9829 | 9832 | 4 | get | `_hasStremioTvGuide` |
| 9834 | 9836 | 3 | get | `_hasStremioTvNext` |
| 9838 | 9839 | 2 | get | `_hasAnyNext` |
| 9841 | 9847 | 7 | method | `_showStremioTvGuideOverlay` |
| 9849 | 9853 | 5 | method | `_hideStremioTvGuide` |
| 9855 | 9860 | 6 | method | `_setStremioTvNextLoading` |
| 9862 | 9884 | 23 | method | `_applyStremioTvGuidePlaybackData` |
| 9886 | 9895 | 10 | method | `_parseStremioTvSources` |
| 9897 | 9988 | 92 | method | `_switchToStremioTvChannel` |
| 9990 | 10057 | 68 | method | `_goToNextStremioTvSlot` |
| 10059 | 10187 | 129 | method | `_goToChannelById` |
| 10189 | 10330 | 142 | method | `_goToNextChannel` |
| 10332 | 10372 | 41 | method | `_goToPreviousEpisode` |
| 10374 | 10419 | 46 | method | `_markCurrentEpisodeAsFinished` |
| 10421 | 10439 | 19 | method | `_markCurrentMovieAsFinished` |
| 10441 | 10477 | 37 | method | `_checkAndApplyLocalCompletion` |
| 10479 | 10502 | 24 | method | `_clearTransitionOnFailure` |
| 10504 | 10560 | 57 | method | `_loadPlaylistIndex` |
| 10562 | 10794 | 233 | method | `_loadPlaylistIndexAttempt` |
| 10796 | 10970 | 175 | method | `_resolvePlaylistEntryUrl` |
| 10972 | 11079 | 108 | method | `_waitForVideoMetadata` |
| 11081 | 11414 | 334 | method | `_playPikPakVideoWithRetry` |
| 11416 | 11474 | 59 | method | `_preloadEpisodeInfo` |
| 11476 | 11498 | 23 | method | `_retryAddonSubtitleFetchAfterSeriesMetadata` |
| 11500 | 11555 | 56 | method | `_fetchSingleFileMovieMetadata` |
| 11557 | 11568 | 12 | method | `_saveImdbIdToPlaylist` |
| 11570 | 11628 | 59 | method | `_saveSeriesPosterToPlaylist` |
| 11630 | 11630 | 1 | field | `_iosPipStarting` |
| 11631 | 11631 | 1 | field | `_iosPipDetached` |
| 11632 | 11632 | 1 | field | `_iosPipSession` |
| 11633 | 11633 | 1 | field | `_lastIosPipPositionSecond` |
| 11635 | 11684 | 50 | method | `_enterPip` |
| 11686 | 11695 | 10 | method | `_armPipAutoEnter` |
| 11697 | 11714 | 18 | method | `_pushPipState` |
| 11716 | 11743 | 28 | method | `_onPipModeChanged` |
| 11745 | 11762 | 18 | method | `_restoreIosPipPlayer` |
| 11764 | 11794 | 31 | method | `_onPipAction` |
| 11796 | 11835 | 40 | method | `_pauseForBackground` |
| 11837 | 11870 | 34 | method | `_resumeFromBackground` |
| 11872 | 11881 | 10 | method | `_syncWakelock` |
| 11883 | 12089 | 207 | method | `dispose` |
| 12091 | 12091 | 1 | field | `_autosaveTimer` |
| 12093 | 12150 | 58 | get | `_resumeKey` |
| 12152 | 12175 | 24 | method | `_torboxResumeKeyForEntry` |
| 12177 | 12188 | 12 | method | `_pikpakResumeKeyForEntry` |
| 12190 | 12204 | 15 | method | `_resumeIdForEntry` |
| 12206 | 12402 | 197 | method | `_maybeRestoreResume` |
| 12404 | 12440 | 37 | method | `_seekForResume` |
| 12442 | 12482 | 41 | method | `_verifyResumeLanding` |
| 12484 | 12526 | 43 | method | `_resumeSeekLanded` |
| 12528 | 12642 | 115 | method | `_getEnhancedPlaybackState` |
| 12644 | 12662 | 19 | method | `_resumeSaveBlocked` |
| 12664 | 12682 | 19 | method | `_observeServerWatch` |
| 12684 | 12703 | 20 | method | `_saveResume` |
| 12705 | 12900 | 196 | method | `_saveResumeLocked` |
| 12902 | 12905 | 4 | field | `_tvAutoHideBlocked` |
| 12907 | 12958 | 52 | method | `_scheduleAutoHide` |
| 12962 | 12978 | 17 | method | `_tvShowBar` |
| 12980 | 12987 | 8 | method | `_tvHideBar` |
| 12989 | 13003 | 15 | method | `_tvScrubBegin` |
| 13005 | 13023 | 19 | method | `_tvScrubStep` |
| 13025 | 13046 | 22 | method | `_tvScrubCommit` |
| 13048 | 13055 | 8 | method | `_tvAbandonScrub` |
| 13057 | 13064 | 8 | method | `_tvScrubCancel` |
| 13066 | 13204 | 139 | method | `_buildTvControls` |
| 13206 | 13214 | 9 | field | `_iptvSheetKey` |
| 13216 | 13221 | 6 | get | `_overlayJustClosed` |
| 13223 | 13229 | 7 | get | `_anyPlayerOverlayOpen` |
| 13231 | 13263 | 33 | method | `_closeTopPlayerOverlay` |
| 13265 | 13282 | 18 | method | `_openTvGuide` |
| 13284 | 13403 | 120 | method | `_handleTvKey` |
| 13405 | 13412 | 8 | method | `_toggleControls` |
| 13414 | 13437 | 24 | method | `_prepareIptvBannerData` |
| 13439 | 13461 | 23 | method | `_raiseIptvZapBanner` |
| 13463 | 13490 | 28 | method | `_onControlsVisibilityChanged` |
| 13492 | 13505 | 14 | method | `_hideIptvZapBanner` |
| 13507 | 13527 | 21 | method | `_syncIptvBannerTicker` |
| 13529 | 13532 | 4 | field | `_iptvArchiveRetryAt` |
| 13534 | 13547 | 14 | method | `_refreshIptvBannerEpgIfEnded` |
| 13549 | 13568 | 20 | method | `_loadIptvZapBannerEpg` |
| 13570 | 13606 | 37 | method | `_handleDoubleTap` |
| 13608 | 13632 | 25 | method | `_onPanStart` |
| 13634 | 13686 | 53 | method | `_onPanUpdate` |
| 13688 | 13704 | 17 | method | `_onPanEnd` |
| 13706 | 13706 | 1 | method | `_format` |
| 13708 | 13723 | 16 | method | `_togglePlay` |
| 13725 | 13737 | 13 | method | `_setManualSelectionMode` |
| 13739 | 13822 | 84 | method | `_cycleAspectMode` |
| 13826 | 13835 | 10 | get | `_sleepTimerMinutesLeft` |
| 13837 | 13842 | 6 | get | `_sleepTimerButtonLabel` |
| 13844 | 13863 | 20 | method | `_showSleepTimerSheet` |
| 13865 | 13877 | 13 | method | `_applySleepTimerSelection` |
| 13879 | 13889 | 11 | method | `_startSleepCountdown` |
| 13891 | 13905 | 15 | method | `_cancelSleepTimer` |
| 13907 | 13918 | 12 | method | `_fireSleepTimer` |
| 13920 | 13929 | 10 | method | `_showSleepTimerToast` |
| 13931 | 13939 | 9 | method | `_changeSpeed` |
| 13941 | 13949 | 9 | method | `_onSpeedButton` |
| 13951 | 13957 | 7 | method | `_onAspectButton` |
| 13959 | 13963 | 5 | method | `_setPlaybackSpeed` |
| 13965 | 13970 | 6 | method | `_setAspectModeDirect` |
| 13972 | 14000 | 29 | method | `_onLongPressStart` |
| 14002 | 14010 | 9 | method | `_onLongPressEnd` |
| 14012 | 14028 | 17 | method | `_toggleOrientation` |
| 14030 | 14030 | 1 | method | `_currentFit` |
| 14042 | 14055 | 14 | method | `_buildSubtitleViewConfig` |
| 14058 | 14069 | 12 | method | `_buildCustomAspectRatioVideo` |
| 14072 | 14078 | 7 | method | `_buildTransitionOverlay` |
| 14080 | 14122 | 43 | method | `_buildStremioTvNextLoadingOverlay` |
| 14124 | 14131 | 8 | get | `_recordingActiveNow` |
| 14133 | 14138 | 6 | get | `_debrifyTvOwnsIdentity` |
| 14140 | 14159 | 20 | method | `_buildDebrifyTvInfoPanel` |
| 14161 | 14170 | 10 | method | `_syncPlaybackClockVisibility` |
| 14172 | 14185 | 14 | method | `_raiseDebrifyBanner` |
| 14187 | 14207 | 21 | method | `_armDebrifyBannerTimer` |
| 14209 | 14219 | 11 | method | `_hideDebrifyBanner` |
| 14221 | 14234 | 14 | method | `_buildIptvInfoPanel` |
| 14237 | 14238 | 2 | method | `_getCustomAspectRatio` |
| 14242 | 14253 | 12 | get | `_canFetchEpisodes` |
| 14255 | 14255 | 1 | field | `_episodeFetchInProgress` |
| 14259 | 14259 | 1 | field | `_syntheticGuidePlaylist` |
| 14260 | 14260 | 1 | field | `_syntheticGuideEntries` |
| 14262 | 14262 | 1 | static | `_pad2` |
| 14264 | 14288 | 25 | method | `_buildSyntheticGuide` |
| 14290 | 14306 | 17 | method | `_packCoversSeason` |
| 14308 | 14513 | 206 | method | `_fetchAndPlayEpisode` |
| 14515 | 14631 | 117 | method | `_tryEpisodeCandidate` |
| 14633 | 14656 | 24 | method | `_resolveAdjacentWithCachedGuide` |
| 14658 | 14674 | 17 | method | `_adjacentEpisode` |
| 14676 | 14698 | 23 | method | `_prepareNextDirectEpisode` |
| 14700 | 14735 | 36 | method | `_showPlaylistSheet` |
| 14737 | 15908 | 1172 | method | `build` |
| 15910 | 15918 | 9 | get | `_isAnyOverlayOpen` |
| 15920 | 15930 | 11 | method | `_wakeControlsOnPointer` |
| 15932 | 15948 | 17 | method | `_currentPlaybackTitleForIdentity` |
| 15950 | 15975 | 26 | method | `_identitySearchInitialQuery` |
| 15977 | 15978 | 2 | method | `_normalisedContentType` |
| 15980 | 15989 | 10 | method | `_subtitleIdentityLabelForSheet` |
| 15991 | 16005 | 15 | method | `_subtitleSearchDisplayLabel` |
| 16007 | 16034 | 28 | method | `_filterIdentitySearchResults` |
| 16036 | 16040 | 5 | method | `_normalisePosterUrl` |
| 16042 | 16050 | 9 | method | `_identityMetaSubtitle` |
| 16052 | 16123 | 72 | method | `_buildIdentifyTitleResultTile` |
| 16125 | 16402 | 278 | method | `_showIdentifyTitleSearchSheet` |
| 16404 | 16431 | 28 | method | `_currentSeasonEpisodeForIdentity` |
| 16433 | 16530 | 98 | method | `_requestSeasonEpisodeForIdentity` |
| 16532 | 16645 | 114 | method | `_identifyTitleAndFetchSubtitles` |
| 16647 | 16825 | 179 | method | `_showTracksSheet` |
| 16829 | 16854 | 26 | method | `_openPlayerMenuAt` |
| 16856 | 16913 | 58 | method | `_openPlayerMenuQuick` |
| 16915 | 16919 | 5 | method | `_hidePlayerMenu` |
| 16921 | 16929 | 9 | method | `_menuApplyTrackChange` |
| 16931 | 16940 | 10 | method | `_audioTrackChoiceChanged` |
| 16942 | 16949 | 8 | method | `_menuSelectAudio` |
| 16951 | 16970 | 20 | method | `_withManualSubtitleChoice` |
| 16972 | 16982 | 11 | method | `_menuSubtitlesOff` |
| 16984 | 17003 | 20 | method | `_menuSelectEmbeddedSubtitle` |
| 17005 | 17045 | 41 | method | `_menuSelectAddonSubtitle` |
| 17047 | 17080 | 34 | method | `_applyStremioSubtitleFromTracksSheet` |
| 17082 | 17162 | 81 | method | `_buildPlayerMenuPanel` |
| 17164 | 17190 | 27 | method | `_resetSubtitleState` |
| 17192 | 17388 | 197 | method | `_restoreTrackPreferences` |
| 17390 | 17442 | 53 | method | `_applyDefaultAudioLanguage` |
| 17444 | 17450 | 7 | get | `_audioAllowsAutomaticSubtitles` |
| 17452 | 17500 | 49 | method | `_refreshSubtitleAudioPolicy` |
| 17502 | 17611 | 110 | method | `_applyDefaultSubtitleLanguage` |
| 17613 | 17640 | 28 | method | `_applyForcedSubtitle` |
| 17642 | 17719 | 78 | method | `_downloadStremioSubtitleToTempFile` |
| 17721 | 17762 | 42 | method | `_applyExternalSubtitleTrack` |
| 17764 | 17774 | 11 | method | `_cleanupTempSubtitleFilesSync` |
| 17776 | 17896 | 121 | method | `_fetchAndMaybeAutoSelectAddonSubtitle` |
| 17898 | 17908 | 11 | method | `_applySubtitleSourcePriority` |
| 17910 | 17968 | 59 | method | `_applySubtitlePriorityUpdate` |
| 17970 | 17983 | 14 | method | `_findSeriesEpisodeForCurrentIndex` |
| 17985 | 18023 | 39 | method | `_persistTrackChoice` |
| 18025 | 18034 | 10 | static | `_subtitlePreferenceMatchesAttempt` |
| 18036 | 18043 | 8 | method | `_generateFilenameHash` |
| 18047 | 18047 | 1 | field | `icon` |
| 18048 | 18048 | 1 | field | `title` |
| 18049 | 18049 | 1 | field | `subtitle` |
| 18050 | 18050 | 1 | field | `onTap` |
| 18052 | 18057 | 6 | ctor | `ctor` |
| 18059 | 18105 | 47 | method | `build` |

## Phase 1 checkpoint R — 2026-10-11

R is `a43f44cbb33a05830bbcb0325c98a768d10cc166`, the format-only
checkpoint: 18,187 physical lines, 157 directives, 8 top-level declarations,
827 class members (725 in State). `vplayer_p1_retained.json` owns every
scanner token in 893 disjoint spans; whole-class rows own their nested
members. The complete analyzer inventory is archived as
`<git-common-dir>/refactor-evidence/vplayer/p1/R-inventory.json`.

The Phase-1 draft below is unapplied. R's AST ranges include declaration
documentation; destinations are relative to `lib/features/video_player/`.
Parameter-only re-proofs and production caller characterization remain Step 0.

| Original | R lines | Draft destination |
|---|---|---|
| `_ManualSourceValidationFailure` | 167–169 | `models/vp_manual_source_validation_failure.dart` |
| `_SeasonEpisodeSelection` | 171–176 | `models/vp_season_episode_selection.dart` |
| `_SubtitleApplyAttempt` | 178–200 | `models/vp_subtitle_apply_attempt.dart` |
| `_IptvZapPage` | 202–223 | `models/vp_iptv_zap_page.dart` |
| `IptvCatchupRequestGate` | 225–254 | `models/iptv_catchup_request_gate.dart` |
| `_RandomChoiceTile` | 18127–18187 | `presentation/vp_random_choice_tile.dart` |
| `_format` | 13773 | `application/vp_format.dart` |
| `_pad2` | 14329 | `application/vp_format.dart` |
| `_generateFilenameHash` | 18117–18124 | `application/vp_filename_hash.dart` |
| `_normalisePosterUrl` | 16103–16107 | `application/vp_identity_text.dart` |
| `_normalisedContentType` | 16044–16045 | `application/vp_identity_text.dart` |
| `_identityMetaSubtitle` | 16109–16117 | `application/vp_identity_text.dart` |
| `_filterIdentitySearchResults` | 16074–16101 | `application/vp_identity_text.dart` |
| `_subtitleSearchDisplayLabel` | 16058–16072 | `application/vp_identity_text.dart` |
| `_diagnosticSubtitleId` | 5073–5074 | `application/vp_subtitle_identity.dart` |
| `_subtitlePreferenceMatchesAttempt` | 18106–18115 | `application/vp_subtitle_identity.dart` |

Source-reader adjustment at Step T: the delayed-startup assertion in
`test/manual_source_validation_contract_test.dart` keeps its original
`_reportStartupFailure` → `_bindPlayerInstanceSubscriptions` anchor and
now matches the complete `current()` guard with whitespace-tolerant syntax.
Formatting split the old one-line prefix. No declaration moved, no assertion
was deleted, and all other source readers/consumer paths remain unchanged.

## Phase 1 Step 0 — original S coverage (2026-10-11)

The application ORIGINAL is S `80839d827383b05078178f292b56efbddd166fb1`,
not a moved implementation. The only application changes from R are the
three H1 interception sites, foundation import and frozen hook scaffolding.
The separate S commit is named the characterization checkpoint. Step 0 adds
only tests, fixtures, source-reading/binding tooling and command registration.
`vplayer_p1.json` remains draft; no production destination exists.

The fake player, native platform and video controller use `implements`, never
a vendored/native constructor. Selected `track` and available `tracks` are
coherent with the broadcast streams, and the real `mkv.Video` subtree mounts.
Factories capture original configurations; `ready` is delivered only after
the original assignments/binds. Frame geometry/readiness, failed/delayed
operations, observers, commands and disposal completion are controllable.
The environment initializes committed profile storage and the synchronous
`ProfilePolicyGuard` mirror, records display/window/SystemChrome calls,
intercepts HTTP and path-provider access, and drains original timers and
leases through bounded pumps. The Flutter binding's pending-timer assertions
remain enabled. Test storage/runtime files stay under Phase-1 evidence.

Every harness command passes `--dart-define=DEBRIFY_VP_TEST_HOOKS=true`; every
file is registered in `dev/tool/ci_behavior_tests.txt`. The installer also has
a no-flag run. Feature move/import/analyzer CI is still deferred to the Step-1
commit creating the first `lib/features/video_player/models/` file.

### Coverage matrix

| Frozen original | Original caller / observable evidence | Tests / mutation proofs |
|---|---|---|
| `_ManualSourceValidationFailure` | Source-sheet pick rejects decoded-media failure, reopens outgoing direct/playlist media at five minutes, never commits rejected row, restores source highlight | `video_player_source_test.dart`; m13–m14 |
| `_SeasonEpisodeSelection` | Identity sheet rejects empty/nonpositive values, accepts trimmed S3E7, cancellation leaves identity unset | `video_player_identity_test.dart`; m11–m12 |
| `_SubtitleApplyAttempt` | Menu selection succeeds; immediate and late decoder failures roll back once; persisted audio identity stays captured after an independent audio event; external subtitle download/persistence/rollback | `video_player_subtitle_test.dart`; m08–m10 |
| `_IptvZapPage` | Channel keys adopt offset-100 window, request offset 102 using adopted source identity, stop at total 104, wrap; underreported total does not fetch beyond the provided window | `video_player_zap_test.dart`; m15–m16, m32 |
| `IptvCatchupRequestGate` | Active completion consumes ticket; cancellation strands it; stale completion preserves newer ticket; original guide callbacks reject late replay after supersession/channel change | `video_player_catchup_gate_test.dart`, `video_player_catchup_caller_test.dart`; m17–m21 |
| `_RandomChoiceTile` | **Dead original.** `_showRandomPlaybackMenu` returns through the constant-true `kUnifiedPlayerMenuEnabled` branch before constructing this legacy widget. The active unified menu's once/continuous choices are characterized; its production flag is unchanged | `video_player_menu_test.dart`; active menu m22. No claim of legacy tile execution |
| `_format` | **Dead original.** Only definition exists in the facade; no caller. Active duration text is rendered by `Controls._format`, a separate implementation. No manufactured caller or behavior change | `video_player_menu_test.dart` renders 02:03 / 20:00; no claim of State `_format` execution |
| `_pad2` | Original playlist action builds synthetic guide filename `S03E07 Plain title`, preserving parsed season/episode | `video_player_menu_test.dart`; m23 |
| `_generateFilenameHash` | `_resumeIdForEntry` fallback for plain playlist with no TorBox/PikPak IDs: existing bookmark restored at three minutes and stored under expected hash; `.mkv`, uppercase `.MP4`, empty entry-title fallback to widget title | `video_player_resume_test.dart`; m05–m07 |
| `_normalisePosterUrl` | Identity result tile uses HTTPS-normalized protocol-relative poster | `video_player_identity_test.dart`; m27 |
| `_normalisedContentType` | Uppercase SERIES search result adopts series identity and opens season/episode dialog | `video_player_identity_test.dart`; m28 |
| `_identityMetaSubtitle` | Rendered Series/Movie, year and addon labels | `video_player_identity_test.dart`; m29 |
| `_filterIdentitySearchResults` | Search caller keeps richer duplicate, filters unsupported type and missing IMDb identity | `video_player_identity_test.dart`; m30 |
| `_subtitleSearchDisplayLabel` | Accepted selection returns and renders `Subtitles for Fixture Series (2024) S3E7` | `video_player_identity_test.dart`; m31 |
| `_diagnosticSubtitleId` | Failed embedded selection logs original requested ID and selection source | `video_player_subtitle_test.dart`; m09 |
| `_subtitlePreferenceMatchesAttempt` | Persisted embedded/external preference is matched to its apply attempt before late-failure rollback; persisted audio owner preserved | `video_player_subtitle_test.dart`; m08, m10 |

All 10 helpers pass the shared analyzer AST lexical-binding scan at S: no
`this`, widget, context, State field/member, service or I/O reference. Exact
application imports are recorded and checked. The already-compiling strict
feature top-level rename probe at R is valid because those helper bodies are
unchanged at S. No helper failed or was transformed/dropped. Evidence:
`parameter-only-S.json`, `parameter-only-S.txt`, `probe-at-R-analyze.txt`.
The two dead originals above are the shared-rule-4 coverage exceptions; both
remain token-frozen in the draft. PiP platform branches remain device-pending
on this desktop harness; no platform-predicate seam or device command is used.

Four launch smoke cases (direct URL, plain playlist, IPTV channel list, Stremio
TV channel) assert configuration, factory order, same player/controller owner,
media URL/headers/play flag, display/orientation calls and clean disposal.
`video_player_mount_test.dart` has m01–m04. The seam guard and installer flag
test have m24–m25. The current per-declaration reader has m26 and real-config
fixtures for repeated relocation, changed body, missing/duplicate fates and
missing current owner. It validates ownership/body/history before returning
live text; it never uses historical text to satisfy a source assertion.
Existing source-test anchors and theme paths need no retarget yet because no
declaration has moved.

### Assertion-failing mutation table

All accepted runs use a detached worktree pinned to S under
`<git-common-dir>/refactor-evidence/vplayer/p1/mutations/original-S`. The
unmutated control passes all 26 tests. Every accepted mutation changes one
analyzer-owned original application declaration, leaves tests unchanged,
and fails an assertion. Compile/load failures and hangs are not kills.
The original source is restored after every run. Exact patches, commands,
JSONL and assertion text are archived as `mutations/runs/mNN.*`; the result
ledgers are `mutation-results.json` and `helper-mutation-results.json`.

| ID | Test | Original declaration mutation | Result |
|---|---|---|---|
| m01 | `video_player_mount_test.dart`: original S mounts direct URL and drains disposal | `_VideoPlayerScreenState._createPlayerInstance`: `logLevel: mk.MPVLogLevel.error → logLevel: mk.MPVLogLevel.warn` | Assertion killed |
| m02 | `video_player_mount_test.dart`: original S mounts playlist and drains disposal | `_VideoPlayerScreenState._createPlayerInstance`: `logLevel: mk.MPVLogLevel.error → logLevel: mk.MPVLogLevel.warn` | Assertion killed |
| m03 | `video_player_mount_test.dart`: original S mounts IPTV channel list and drains disposal | `_VideoPlayerScreenState._createPlayerInstance`: `logLevel: mk.MPVLogLevel.error → logLevel: mk.MPVLogLevel.warn` | Assertion killed |
| m04 | `video_player_mount_test.dart`: original S mounts Stremio TV channel and drains disposal | `_VideoPlayerScreenState._createPlayerInstance`: `logLevel: mk.MPVLogLevel.error → logLevel: mk.MPVLogLevel.warn` | Assertion killed |
| m05 | `video_player_resume_test.dart`: fallback resume identity restores bookmark for "Plain.Movie.mkv" | `_VideoPlayerScreenState._generateFilenameHash`: `nameWithoutExt.hashCode.toString() → (nameWithoutExt + 'mutated').hashCode.toString()` | Assertion killed |
| m06 | `video_player_resume_test.dart`: fallback resume identity restores bookmark for "Plain.Movie.MP4" | `_VideoPlayerScreenState._generateFilenameHash`: `nameWithoutExt.hashCode.toString() → (nameWithoutExt + 'mutated').hashCode.toString()` | Assertion killed |
| m07 | `video_player_resume_test.dart`: fallback resume identity restores bookmark for "" | `_VideoPlayerScreenState._generateFilenameHash`: `nameWithoutExt.hashCode.toString() → (nameWithoutExt + 'mutated').hashCode.toString()` | Assertion killed |
| m08 | `video_player_subtitle_test.dart`: subtitle success then late failure restores selection with the persisted audio identity | `_VideoPlayerScreenState._persistTrackChoice`: `attempt.persistedAudioId = audio; → attempt.persistedAudioId = '2';` | Assertion killed |
| m09 | `video_player_subtitle_test.dart`: subtitle rejected apply rolls back once and reports the original diagnostic id | `_VideoPlayerScreenState._diagnosticSubtitleId`: `'<external>' : track.id → '<external>' : 'wrong-id'` | Assertion killed |
| m10 | `video_player_subtitle_test.dart`: external subtitle apply persists its addon identity and rolls back after a decoder error | `_VideoPlayerScreenState._subtitlePreferenceMatchesAttempt`: `return subtitle.startsWith('stremio:'); → return false;` | Assertion killed |
| m11 | `video_player_identity_test.dart`: identity search filters and labels results then validates and accepts the season episode | `_VideoPlayerScreenState._requestSeasonEpisodeForIdentity`: `_SeasonEpisodeSelection(season: season, episode: episode) → _SeasonEpisodeSelection(season: season, episode: episode + 1)` | Assertion killed |
| m12 | `video_player_identity_test.dart`: identity search filters and labels results then cancels the season episode | `_VideoPlayerScreenState._requestSeasonEpisodeForIdentity`: `() => Navigator.of(dialogContext).pop(), → () => Navigator.of(dialogContext).pop(const _SeasonEpisodeSelection(season: 1, episode: 1)),` | Assertion killed |
| m13 | `video_player_source_test.dart`: manual direct source rejection restores outgoing media and position | `_VideoPlayerScreenState._switchToStremioSource`: `_currentSourceIndex = previousSourceIndex; → _currentSourceIndex = index;` | Assertion killed |
| m14 | `video_player_source_test.dart`: manual playlist source rejection restores outgoing media and position | `_VideoPlayerScreenState._switchToSourcePlaylist`: `_currentSourceIndex = outgoingSourceIndex; → _currentSourceIndex = sourceIndex;` | Assertion killed |
| m15 | `video_player_zap_test.dart`: IPTV zap preserves nonzero page offsets and fetches the next page | `_VideoPlayerScreenState._parseIptvZapPage`: `final offset = rawOffset is num ? math.max(0, rawOffset.toInt()) : 0; → final offset = 0;` | Assertion killed |
| m16 | `video_player_zap_test.dart`: IPTV zap preserves nonzero page offsets and clamps the reported total | `_VideoPlayerScreenState._parseIptvZapPage`: `total: math.max(total, offset + channels.length), → total: math.max(total, offset + channels.length) + 2,` | Assertion killed |
| m17 | `video_player_catchup_gate_test.dart`: catchup completion consumes only the active ticket | `IptvCatchupRequestGate.complete`: `_activeTicket = null; → _activeTicket = ticket;` | Assertion killed |
| m18 | `video_player_catchup_gate_test.dart`: catchup cancellation invalidates the ticket without accepting stale completion | `IptvCatchupRequestGate.cancel`: `_activeTicket = null; → _activeTicket = _generation;` | Assertion killed |
| m19 | `video_player_catchup_gate_test.dart`: catchup stale completion cannot consume a newer lookup | `IptvCatchupRequestGate.complete`: `if (!isCurrent(ticket)) return false; → if (false) return false;` | Assertion killed |
| m20 | `video_player_catchup_caller_test.dart`: original catchup caller ignores a superseded replay lookup | `IptvCatchupRequestGate.isCurrent`: `_activeTicket == ticket && _generation == ticket → true` | Assertion killed |
| m21 | `video_player_catchup_caller_test.dart`: original catchup caller cancels on channel change | `IptvCatchupRequestGate.isCurrent`: `_activeTicket == ticket && _generation == ticket → true` | Assertion killed |
| m22 | `video_player_menu_test.dart`: active random menu dispatches once and continuous choices | `_VideoPlayerScreenState._toggleContinuousShuffle`: `_continuousShuffleEnabled = true; → _continuousShuffleEnabled = false;` | Assertion killed |
| m23 | `video_player_menu_test.dart`: original controls render duration and synthetic guide stamps padded episode identity | `_VideoPlayerScreenState._pad2`: `padLeft(2, '0') → padLeft(1, '0')` | Assertion killed |
| m24 | `video_player_seam_guard_test.dart`: S has only the frozen installer and once-only default paths | `_VideoPlayerScreenState._createPlayerInstance`: `logLevel: mk.MPVLogLevel.error → logLevel: mk.MPVLogLevel.warn` | Assertion killed |
| m25 | `video_player_seam_guard_test.dart`: installation requires the explicit test-only compile-time flag | `VideoPlayerScreenTestHooks.install`: `if (!const bool.fromEnvironment('DEBRIFY_VP_TEST_HOOKS')) → if (const bool.fromEnvironment('DEBRIFY_VP_TEST_HOOKS'))` | Assertion killed |
| m26 | `video_player_source_reader_test.dart`: declaration reader validates current ownership and chains repeated relocation | `_VideoPlayerScreenState._generateFilenameHash`: `nameWithoutExt.hashCode.toString() → (nameWithoutExt + 'mutated').hashCode.toString()` | Assertion killed |
| m27 | `video_player_identity_test.dart`: identity search filters and labels results then validates and accepts the season episode | `_VideoPlayerScreenState._normalisePosterUrl`: `return 'https:$url'; → return url;` | Assertion killed |
| m28 | `video_player_identity_test.dart`: identity search filters and labels results then validates and accepts the season episode | `_VideoPlayerScreenState._normalisedContentType`: `type.toLowerCase() == 'series' → type == 'series'` | Assertion killed |
| m29 | `video_player_identity_test.dart`: identity search filters and labels results then validates and accepts the season episode | `_VideoPlayerScreenState._identityMetaSubtitle`: `return parts.join(' \| '); → return parts.join(' / ');` | Assertion killed |
| m30 | `video_player_identity_test.dart`: identity search filters and labels results then validates and accepts the season episode | `_VideoPlayerScreenState._filterIdentitySearchResults`: `if (newScore > existingScore) → if (newScore < existingScore)` | Assertion killed |
| m31 | `video_player_identity_test.dart`: identity search filters and labels results then validates and accepts the season episode | `_VideoPlayerScreenState._subtitleSearchDisplayLabel`: `return '$title S${season}E$episode'; → return '$title';` | Assertion killed |
| m32 | `video_player_zap_test.dart`: IPTV zap preserves nonzero page offsets and fetches the next page | `_VideoPlayerScreenState._parseIptvZapPage`: `total: math.max(total, offset + channels.length), → total: offset + channels.length,` | Assertion killed |

One discarded offset-zero experiment created a paging microtask loop, was
interrupted, and is explicitly excluded (`discarded-offset-loop/NOTE.txt`).
Its replacement m16 changes the total and fails the unchanged no-next-page
assertion. No assertion, timeout or original behavior was weakened.

### Original-suite profile-editor NOTE

The extra original-suite failure, `profile editor keeps feature controls
hidden behind one switch`, was a deterministic parser-path setup failure: the
existing reader requires `.dart_tool/edit_profile_parser/` inside its path.
The evidence-only wrapper now nests that component under the required isolated
`.dart_tool/vplayer_parser/` root, copying a fresh package and deleting kernels.
Three valid isolated reruns pass unchanged source/test. Classification:
environment/tool-routing incompatibility, not an observed behavior flake or
application regression. No allowlist entry was added. Initial incompatible
reruns and the valid 3x runs remain archived with `profile-editor-NOTE.txt`.

The final full-suite comparison is recorded after the Step-0 test commit.
The incomplete pre-lint-cleanup run is excluded (`step0-suite-NOTE.txt`).
