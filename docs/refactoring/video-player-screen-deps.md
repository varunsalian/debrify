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
| `_format` | **Step-0 claim corrected in Step 0b:** the State method is passed as a tear-off to `SeekHud`; the original control-duration test only executes separate `Controls._format` | Step 0b adds mounted pan/HUD target and delta assertions in `video_player_menu_test.dart`; c19/f01 |
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
The `_RandomChoiceTile` dead original is the shared-rule-4 coverage exception.
Step 0b corrects the initial `_format` dead-code claim and closes its HUD gap;
both declarations remain token-frozen in the draft. PiP platform branches remain device-pending
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

### Step-0 complete baseline

At `c502380169cbc3a1394782c52a0fac08d7595e67`, the complete
`step0-suite-isolated.jsonl` has 12,820 successes, 13 failures, 28 errors and
20 skips. `suite_evidence.py compare` against `original-suite-routed.jsonl`
passes: exactly 26 added successful identities, no new failures, no missing
tests and no new skips. The only changed original outcome is the repaired
profile-editor parser setup failure. SDK/configuration is unchanged; the
tested tree stayed fixed throughout the run. `step0-baseline-outcomes.json`
is the new observed baseline, with the exact delta in
`step0-baseline-delta.json`; neither replaces a checked-in failure allowlist.

`step0-suite-final.jsonl` is also incomplete/excluded: auditing found nested
contract guards with hard-coded parser packages even though their outer
CLI option was isolated. The final evidence-only routing adapter redirects
every shared AST parse/ensure call, including child tools, to the fresh
worktree-local package selected before argument parsing. No repository
checker/manifest behavior changed. `parser-routing-audit.json` records the
unique isolated packages, deleted copied kernels and nested redirects.

Final root analysis (`step0-analyze-complete.txt`) has exactly T's 1,753
diagnostic identities/counts. The scoped comparator retains all 73 S
identities with zero additions; the new harness folder has zero issues.
Earlier temporary build/vendor/test scan differences are excluded from
that final claim and archived separately.

## Phase 1 Step 0b — systematic original mutation sweep (2026-10-11)

Claude's initial independent sample killed only 7/17 valid mutations (41%).
This checkpoint therefore inventories every frozen declaration, rather than
only repairing its listed survivors. All behavior and mutation runs still
target ORIGINAL `c502380169cbc3a1394782c52a0fac08d7595e67`; its application
source is byte-identical to S `80839d827383b05078178f292b56efbddd166fb1`.
There are no production moves, new seams, private-call adapters or bug fixes.

The analyzer inventory enumerates **248 nested statement, branch, literal,
expression and constructor-binding sites across all 16 declarations**.
Related nested nodes share a semantic mutation; they are not counted as
independent kills. The systematic campaign has **113 valid mutations: 107
assertion kills and six proved original-caller equivalents**, with no
unclassified site or surviving non-equivalent behavior. The exception marker
has an empty const constructor and zero mutation sites. The unreachable
`_RandomChoiceTile` accounts for 26 dead sites under shared rule 4. The Step-0
claim that State `_format` was dead is corrected: `SeekHud` receives its tear-off.

The checkpoint adds **31 successful test identities**. Each new test itself
fails at least one accepted original-application mutation; the per-test witness
ledger is `step0b/new-test-mutation-witnesses.json`. All additions assert runtime
widgets, callbacks, player commands, preferences, navigation or diagnostic
output through existing original callers. Source guard/reader tests are excluded
from mutation scores. Default Flutter pending-timer assertions remain enabled.
The direct gate tests additionally exercise its existing public API.

All evidence below is under
`<git-common-dir>/refactor-evidence/vplayer/p1/step0b/`. The detached worktree
`original/` stays pinned to c50238016; each patch changes one analyzer-owned
original declaration and restores source afterwards. `SETUP.json` and
`test-inputs-complete.json` record the original and complete final test inputs
(the earlier `test-inputs-final.json` predates the added seek-HUD test). Accepted
patches, commands, raw JSONL, stderr and assertion identities are in
`sample/` and `sweep/`; canonical ledgers are `sample-results.json` and
`systematic-coverage.json`. `ast-points.json` and the latter ledger retain every
site, exact source offsets/text, semantic mutation links and equivalence reasons.
Each AST invocation uses a fresh isolated parser under
`.dart_tool/vplayer_parser/`, with copied kernels deleted. Processes use
`nice -n 19`; Flutter test runs are serialized.

### Updated frozen-declaration coverage matrix

| Frozen original | Enumerated sites | Original caller / observable contract | Tests and mutation witnesses |
|---|---:|---|---|
| `_ManualSourceValidationFailure` | 0 | Original source pick / rejected-source rollback and reopened outgoing position | `video_player_source_test.dart`; empty const exception marker has zero mutation sites; Step-0 m13/m14 cover construct/catch |
| `_SeasonEpisodeSelection` | 4 | Identity search dialog / adopted season and episode; existing pair reuse | `video_player_identity_test.dart`, `video_player_identity_edges_test.dart`; s13/s14 |
| `_SubtitleApplyAttempt` | 22 | Mounted menu, automatic restore and decoder-error caller / pending, rejected, successful, superseded and late-failure ownership; persisted audio, previous addon and sync path | `video_player_subtitle_test.dart`, `video_player_subtitle_edges_test.dart`; s01–s12 |
| `_IptvZapPage` | 12 | Original ChannelUp callback / channels, page offset/total/source and replacement category lists across News→Sports→Movies | `video_player_zap_test.dart`, `video_player_zap_categories_test.dart`; s15–s20 |
| `IptvCatchupRequestGate` | 34 | Public begin/cancel/complete/isCurrent and original asynchronous guide callbacks / exact tickets, stale and active completion, idle cancellation, 4096 histories | `video_player_catchup_gate_test.dart`, `video_player_catchup_caller_test.dart`; g01–g16, c15/c16 |
| `_diagnosticSubtitleId` | 4 | Original failed embedded/data/addon apply / runtime requestedId log redaction and source | `video_player_subtitle_test.dart`, `video_player_subtitle_edges_test.dart`; h06–h09 |
| `_format` | 1 | Mounted original pan callbacks publish SeekHud / rendered target and signed delta in minutes, hours and reverse seek; committed seek and HUD expiry | `video_player_menu_test.dart`; f01/c19; State tear-off is reachable, correcting the Step-0 dead-code claim |
| `_pad2` | 3 | Original playlist action / synthetic guide filename for S3E7 and S12E34 | `video_player_menu_test.dart`; h01/h02/h24, uniquely scoped c1 |
| `_normalisedContentType` | 6 | Original identity search/adoption / uppercase movie and series, unsupported type rejection | `video_player_identity_test.dart`, `video_player_identity_edges_test.dart`; h03–h05/h25, i11/i42/i44 |
| `_subtitleSearchDisplayLabel` | 21 | Search selection then mounted player menu / absent, empty and trimmed year; movie without dialog; existing or prompted series episode suffix | `video_player_identity_test.dart`, `video_player_identity_edges_test.dart`; i01–i09 |
| `_filterIdentitySearchResults` | 65 | HTTP-backed real Stremio search caller / empty result, IMDb/type filtering, namespaces, first-wins ties, each score term, poster>year in both orders, result insertion order | `video_player_identity_test.dart`, `video_player_identity_edges_test.dart`; i10–i28/i42–i43/i45–i49/i51 |
| `_normalisePosterUrl` | 11 | Identity search result / Image.network URL or its absence for null/whitespace | `video_player_identity_test.dart`, `video_player_identity_edges_test.dart`; i29–i33 |
| `_identityMetaSubtitle` | 20 | Identity search tile / Movie/Series, original year text, empty and named addon, separator | `video_player_identity_test.dart`, `video_player_identity_edges_test.dart`; i34–i41/i44 |
| `_subtitlePreferenceMatchesAttempt` | 12 | Original preference write/decoder rollback / off, embedded, URI and data tracks; live stale menu snapshots and malformed stremio prefix | `video_player_subtitle_test.dart`, `video_player_subtitle_edges_test.dart`; h10–h17 |
| `_generateFilenameHash` | 7 | Fallback resume caller / actual bookmark seek and storage identity for multiple dots, uppercase extension, title fallback, no extension, trailing dot and dotfile | `video_player_resume_test.dart`; h18–h23/h26 |
| `_RandomChoiceTile` | 26 | Dead original: both constructions follow the constant-true unified-menu return | c18 survives; all 26 sites unreachable; active menu remains exercised by `video_player_menu_test.dart` |

### Claude's 20-mutation rerun

The exact requested sample, including c1's unique complete `_pad2` declaration,
has **18 assertion kills / 20 valid runs (90%)**. Its two survivors are
proved equivalent/unreachable, not accepted gaps: 18/18 non-equivalent mutations
are killed. Compilation failures and loops never count as kills.

| ID | Original mutation | Result / assertion witness |
|---|---|---|
| c1 | _pad2 unique declaration: padLeft width 2→3 | Assertion killed: original controls render duration and synthetic guide stamps padded episode identity; synthetic guide preserves two-digit season and episode |
| c2 | Filename hash: remove extension normalization | Assertion killed: fallback resume identity restores bookmark for "Plain.Movie.mkv"; fallback resume identity restores bookmark for "Plain.Movie.MP4"; fallback resume identity restores bookmark for ""; fallback resume identity restores bookmark for "Trailing."; fallback resume identity restores bookmark for ".hidden" |
| c3 | Protocol-relative poster: https→http | Assertion killed: identity search filters and labels results then validates and accepts the season episode; identity search filters and labels results then cancels the season episode |
| c4 | Normalized non-series type: movie→series | Assertion killed: identity year presence improves equally illustrated duplicate "2025"; identity year presence improves equally illustrated duplicate "   "; movie identity adopts without episode prompt for year "null"; movie identity adopts without episode prompt for year "   "; movie identity adopts without episode prompt for year " 2025 "; identity search rejects custom series ids and keeps type namespaces; identity duplicate ranking prefers poster over year in forward order; identity duplicate ranking prefers poster over year in reverse order; identity zero scores keep first title and original result order; identity equal scores keep first title and original result order |
| c5 | Identity tile series label: Series→Movie | Assertion killed: identity search filters and labels results then validates and accepts the season episode; identity search filters and labels results then cancels the season episode |
| c6 | Identity tile separator: vertical bar→dash | Assertion killed: identity search filters and labels results then validates and accepts the season episode; identity search filters and labels results then cancels the season episode; movie identity adopts without episode prompt for year " 2025 " |
| c7 | Identity filter: accept IMDb identities without tt prefix | Assertion killed: identity search rejects custom series ids and keeps type namespaces |
| c8 | Equal-score duplicate: >→>= replaces first | Assertion killed: identity zero scores keep first title and original result order; identity equal scores keep first title and original result order |
| c9 | Existing duplicate score: swap poster/year weights | Assertion killed: identity duplicate ranking prefers poster over year in reverse order |
| c10 | Subtitle search label: swap season/episode | Assertion killed: identity search filters and labels results then validates and accepts the season episode; series identity reuses launch episode and keeps absolute poster URL; series identity preserves a single-slash poster URL |
| c11 | Subtitle search year label: parentheses→brackets | Assertion killed: identity year presence improves equally illustrated duplicate "2025"; identity search filters and labels results then validates and accepts the season episode; movie identity adopts without episode prompt for year " 2025 "; identity equal scores keep first title and original result order |
| c12 | Diagnostic ID: omit data-track redaction | Assertion killed: data subtitle rejection redacts contents in diagnostic id |
| c13 | Off requested: accept any persisted subtitle identity | Assertion killed: off attempt ignores unrelated audio preference identity |
| c14 | External preference prefix: stremio:→stremio | Assertion killed: external attempt ignores unrelated audio preference identity |
| c15 | Gate isCurrent: remove generation conjunction | Equivalent: active ticket is null or equals generation at every public method boundary |
| c16 | Gate cancel: remove generation increment | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| c17 | Gate complete: retain active ticket | Assertion killed: catchup cancellation advances public ticket generation before next lookup; catchup ownership holds across every six-action request history; catchup completion consumes only the active ticket |
| c18 | Legacy RandomChoiceTile subtitle Text: subtitle→title | Dead original: const-true unified-menu branch returns before both constructions |
| c19 | State _format passed to SeekHud: formatDuration→Duration.toString | Assertion killed: horizontal seek HUD formats original target and signed delta |
| c20 | SubtitleApplyAttempt persisted default: false→true | Assertion killed: data apply does not claim an embedded preference as addon persistence; automatic restored subtitle failure leaves saved preference untouched |

**c15 confirmed equivalent; c16 refuted.** The gate invariant starts with no
active ticket. `begin` establishes active=generation; successful `complete`
and `cancel` clear active; rejected operations leave it unchanged. Induction
therefore makes c15's conjunction redundant for all public histories, also
checked across all 4096 six-action histories. In contrast, public ticket
values expose c16: `begin()`=1, `cancel()`=true, next `begin()`=3; c16 returns 2.
The new exact-ticket test assertion-kills it. Ownership booleans alone miss
this difference. `reachability-proofs.json` records the invariant and counterexample.

**c18 is an original dead-code exception, not covered behavior.** The only
two `_RandomChoiceTile` constructions are after `_showRandomPlaybackMenu`'s
return under `const bool kUnifiedPlayerMenuEnabled = true` in the imported
player-menu library. The analyzer token inventory and exact caller/constant
text are archived in `reachability-proofs.json`. No fabricated caller, flag
change or additional seam is used to claim a kill.

**c19 is a real behavior gap, now closed.** The earlier Step-0 report and an
initial Step-0b call-only search missed `SeekHud(hud: hud, format: _format)`.
The new mounted pan-callback test renders the actual HUD's minutes/hours target
and signed delta, including the original double-minus reverse-seek text,
commits the seek and checks HUD expiry. c19/f01 assertion-fail this test.
Controls duration assertions remain separate; application behavior is unchanged.

### Systematic statement / branch / literal mutation table

Every row is a valid completed run on the original. The full patch and all
failing assertion identities are retained in the canonical ledger; the table
uses one witness per killed row for readability. Constructor rows modify one
forwarded field only. E1–E6 below are equivalents, excluded from kill counts.

| ID | Frozen original | Semantic change | Result / witness |
|---|---|---|---|
| s01 | `_SubtitleApplyAttempt` | `bool failed = false;` → `bool failed = true;` | Assertion killed: subtitle success then late failure restores selection with the persisted audio identity |
| s02 | `_SubtitleApplyAttempt` | `bool handled = false;` → `bool handled = true;` | Assertion killed: subtitle success then late failure restores selection with the persisted audio identity |
| s03 | `_SubtitleApplyAttempt` | `bool successReturned = false;` → `bool successReturned = true;` | Assertion killed: audio write during pending subtitle apply is not owned by unfinished attempt |
| s04 | `_SubtitleApplyAttempt` | `bool persisted = false;` → `bool persisted = true;` | Assertion killed: data apply does not claim an embedded preference as addon persistence |
| s05 | `_SubtitleApplyAttempt` | Constructor forwarding: generation = generation + 1 | Assertion killed: subtitle success then late failure restores selection with the persisted audio identity |
| s06 | `_SubtitleApplyAttempt` | Constructor forwarding: requested = previous | Assertion killed: audio write during pending subtitle apply is not owned by unfinished attempt |
| s07 | `_SubtitleApplyAttempt` | Constructor forwarding: previous = requested | Assertion killed: audio write during pending subtitle apply is not owned by unfinished attempt |
| s08 | `_SubtitleApplyAttempt` | Constructor forwarding: source = 'wrong-source' | Assertion killed: data subtitle rejection redacts contents in diagnostic id |
| s09 | `_SubtitleApplyAttempt` | Constructor forwarding: previousStremioId = null | Assertion killed: late embedded failure restores previous addon selection once |
| s10 | `_SubtitleApplyAttempt` | Constructor forwarding: previousExternalPath = null | Assertion killed: late embedded failure restores previous addon selection once |
| s11 | `_SubtitleApplyAttempt` | `String? persistedAudioId;` → `String? persistedAudioId = 'wrong-audio';` | Equivalent E1 |
| s12 | `_SubtitleApplyAttempt` | `Completer<void>? persistenceDone;` → `Completer<void>? persistenceDone = Completer<void>()..complete();` | Equivalent E2 |
| s13 | `_SeasonEpisodeSelection` | Constructor forwarding: season = season + 1 | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| s14 | `_SeasonEpisodeSelection` | Constructor forwarding: episode = episode + 1 | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| s15 | `_IptvZapPage` | Constructor forwarding: channels = const [] | Assertion killed: IPTV zap preserves nonzero page offsets and fetches the next page |
| s16 | `_IptvZapPage` | Constructor forwarding: offset = offset + 1 | Assertion killed: IPTV zap preserves nonzero page offsets and fetches the next page |
| s17 | `_IptvZapPage` | Constructor forwarding: total = total + 1 | Assertion killed: IPTV zap preserves nonzero page offsets and clamps the reported total |
| s18 | `_IptvZapPage` | Constructor forwarding: sourceId = null | Assertion killed: IPTV zap preserves nonzero page offsets and fetches the next page |
| s19 | `_IptvZapPage` | Constructor forwarding: category = null | Assertion killed: IPTV category crossing carries page category source and replacement directory |
| s20 | `_IptvZapPage` | Constructor forwarding: categories = const [] | Assertion killed: IPTV category crossing carries page category source and replacement directory |
| g01 | `IptvCatchupRequestGate` | `int _generation = 0;` → `int _generation = 1;` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g02 | `IptvCatchupRequestGate` | `int? _activeTicket;` → `int? _activeTicket = 0;` | Assertion killed: catchup ownership holds across every six-action request history |
| g03 | `IptvCatchupRequestGate.begin` | `++_generation` → `_generation` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g04 | `IptvCatchupRequestGate.begin` | `_activeTicket = ticket;` → `_activeTicket = null;` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g05 | `IptvCatchupRequestGate.begin` | `return ticket;` → `return ticket + 1;` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g06 | `IptvCatchupRequestGate.isCurrent` | `_activeTicket == ticket` → `_activeTicket != ticket` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g07 | `IptvCatchupRequestGate.isCurrent` | `_generation == ticket` → `_generation != ticket` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g08 | `IptvCatchupRequestGate.complete` | `if (!isCurrent(ticket)) return false;` → `if (isCurrent(ticket)) return false;` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g09 | `IptvCatchupRequestGate.complete` | `return false;` → `return true;` | Assertion killed: catchup ownership holds across every six-action request history |
| g10 | `IptvCatchupRequestGate.complete` | `_activeTicket = null;` → `_activeTicket = ticket;` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g11 | `IptvCatchupRequestGate.complete` | `return true;` → `return false;` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g12 | `IptvCatchupRequestGate.cancel` | `if (_activeTicket == null) return false;` → `if (_activeTicket != null) return false;` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g13 | `IptvCatchupRequestGate.cancel` | `return false;` → `return true;` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g14 | `IptvCatchupRequestGate.cancel` | `_generation++;` → `(deleted)` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| g15 | `IptvCatchupRequestGate.cancel` | `_activeTicket = null;` → `_activeTicket = _generation;` | Assertion killed: catchup ownership holds across every six-action request history |
| g16 | `IptvCatchupRequestGate.cancel` | `return true;` → `return false;` | Assertion killed: catchup cancellation advances public ticket generation before next lookup |
| h01 | `_pad2` | `padLeft(2, '0')` → `padLeft(2, 'x')` | Assertion killed: original controls render duration and synthetic guide stamps padded episode identity |
| h02 | `_pad2` | `padLeft(2, '0')` → `padLeft(1, '0')` | Assertion killed: original controls render duration and synthetic guide stamps padded episode identity |
| h03 | `_normalisedContentType` | `type.toLowerCase() == 'series'` → `type == 'series'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| h04 | `_normalisedContentType` | `? 'series' : 'movie'` → `? 'movie' : 'movie'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| h05 | `_normalisedContentType` | `? 'series' : 'movie'` → `? 'series' : 'series'` | Assertion killed: identity year presence improves equally illustrated duplicate "2025" |
| h06 | `_diagnosticSubtitleId` | `track.uri \|\| track.data` → `track.data` | Assertion killed: uri subtitle rejection redacts file path in diagnostic id |
| h07 | `_diagnosticSubtitleId` | `track.uri \|\| track.data` → `track.uri` | Assertion killed: data subtitle rejection redacts contents in diagnostic id |
| h08 | `_diagnosticSubtitleId` | `'<external>'` → `'<changed>'` | Assertion killed: data subtitle rejection redacts contents in diagnostic id |
| h09 | `_diagnosticSubtitleId` | `track.id;` → `'wrong-id';` | Assertion killed: subtitle rejected apply rolls back once and reports the original diagnostic id |
| h10 | `_subtitlePreferenceMatchesAttempt` | `attempt.requested.id == 'no'` → `attempt.requested.id != 'no'` | Assertion killed: subtitle success then late failure restores selection with the persisted audio identity |
| h11 | `_subtitlePreferenceMatchesAttempt` | `return subtitle == 'no';` → `return true;` | Assertion killed: off attempt ignores unrelated audio preference identity |
| h12 | `_subtitlePreferenceMatchesAttempt` | `return subtitle == 'no';` → `return false;` | Assertion killed: off attempt ignores unrelated audio preference identity |
| h13 | `_subtitlePreferenceMatchesAttempt` | `attempt.requested.uri \|\| attempt.requested.data` → `attempt.requested.data` | Assertion killed: external subtitle apply persists its addon identity and rolls back after a decoder error |
| h14 | `_subtitlePreferenceMatchesAttempt` | `attempt.requested.uri \|\| attempt.requested.data` → `attempt.requested.uri` | Assertion killed: data apply does not claim an embedded preference as addon persistence |
| h15 | `_subtitlePreferenceMatchesAttempt` | `return subtitle.startsWith('stremio:');` → `return subtitle.startsWith('stremio');` | Assertion killed: external attempt ignores unrelated audio preference identity |
| h16 | `_subtitlePreferenceMatchesAttempt` | `return subtitle == attempt.requested.id;` → `return false;` | Assertion killed: subtitle success then late failure restores selection with the persisted audio identity |
| h17 | `_subtitlePreferenceMatchesAttempt` | `return subtitle == attempt.requested.id;` → `return true;` | Assertion killed: embedded attempt ignores unrelated audio preference identity |
| h18 | `_generateFilenameHash` | `RegExp(r'\.[^.]*$')` → `RegExp(r'\.[^.]+$')` | Assertion killed: fallback resume identity restores bookmark for "Trailing." |
| h19 | `_generateFilenameHash` | `RegExp(r'\.[^.]*$')` → `RegExp(r'\..*$')` | Assertion killed: fallback resume identity restores bookmark for "Plain.Movie.mkv" |
| h20 | `_generateFilenameHash` | `RegExp(r'\.[^.]*$')` → `RegExp(r'[^.]*$')` | Assertion killed: fallback resume identity restores bookmark for "Plain.Movie.mkv" |
| h21 | `_generateFilenameHash` | `RegExp(r'\.[^.]*$'), ''` → `RegExp(r'\.[^.]*$'), 'x'` | Assertion killed: fallback resume identity restores bookmark for "Plain.Movie.mkv" |
| h22 | `_generateFilenameHash` | `nameWithoutExt.hashCode.toString()` → `filename.hashCode.toString()` | Assertion killed: fallback resume identity restores bookmark for "Plain.Movie.mkv" |
| h23 | `_generateFilenameHash` | `return hash;` → `return 'wrong';` | Assertion killed: fallback resume identity restores bookmark for "Plain.Movie.mkv" |
| i01 | `_subtitleSearchDisplayLabel` | `meta.year?.trim()` → `meta.year` | Assertion killed: identity year presence improves equally illustrated duplicate "   " |
| i02 | `_subtitleSearchDisplayLabel` | `year != null && year.isNotEmpty` → `year != null` | Assertion killed: identity year presence improves equally illustrated duplicate "   " |
| i03 | `_subtitleSearchDisplayLabel` | `? '${meta.name} ($year)'` → `? '${meta.name} [$year]'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i04 | `_subtitleSearchDisplayLabel` | `: meta.name;` → `: 'wrong';` | Assertion killed: identity year presence improves equally illustrated duplicate "   " |
| i05 | `_subtitleSearchDisplayLabel` | `contentType == 'series'` → `contentType != 'series'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i06 | `_subtitleSearchDisplayLabel` | `&& season != null` → `(deleted)` | Equivalent E3 |
| i07 | `_subtitleSearchDisplayLabel` | `&& episode != null` → `(deleted)` | Equivalent E4 |
| i08 | `_subtitleSearchDisplayLabel` | `return '$title S${season}E$episode';` → `return '$title S${episode}E$season';` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i09 | `_subtitleSearchDisplayLabel` | `return title;` → `return '$title S${season}E$episode';` | Assertion killed: identity year presence improves equally illustrated duplicate "2025" |
| i10 | `_filterIdentitySearchResults` | `for (final meta in metas)` → `for (final meta in metas.reversed)` | Assertion killed: identity zero scores keep first title and original result order |
| i11 | `_filterIdentitySearchResults` | `imdbId == null \|\| !imdbId.startsWith('tt')` → `imdbId == null` | Assertion killed: identity search rejects custom series ids and keeps type namespaces |
| i12 | `_filterIdentitySearchResults` | `type != 'movie' && type != 'series'` → `type != 'movie' \|\| type != 'series'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i13 | `_filterIdentitySearchResults` | `type != 'movie' && type != 'series'` → `false` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i14 | `_filterIdentitySearchResults` | `meta.type.toLowerCase()` → `meta.type` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i15 | `_filterIdentitySearchResults` | `'$type:$imdbId'` → `'$imdbId'` | Assertion killed: identity search rejects custom series ids and keeps type namespaces |
| i16 | `_filterIdentitySearchResults` | `bestByKey[key] = meta;` → `(deleted)` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i17 | `_filterIdentitySearchResults` | `bestByKey[key] = meta;` → `(deleted)` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i18 | `_filterIdentitySearchResults` | `if (newScore > existingScore)` → `if (newScore >= existingScore)` | Assertion killed: identity zero scores keep first title and original result order |
| i19 | `_filterIdentitySearchResults` | `if (newScore > existingScore)` → `if (newScore < existingScore)` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i20 | `_filterIdentitySearchResults` | `(existing.poster != null ? 2 : 0)` → `(existing.poster != null ? 0 : 0)` | Assertion killed: identity duplicate ranking prefers poster over year in forward order |
| i21 | `_filterIdentitySearchResults` | `(existing.year != null ? 1 : 0)` → `(existing.year != null ? 0 : 0)` | Assertion killed: identity equal scores keep first title and original result order |
| i22 | `_filterIdentitySearchResults` | `(meta.poster != null ? 2 : 0)` → `(meta.poster != null ? 0 : 0)` | Assertion killed: identity year presence improves equally illustrated duplicate "2025" |
| i23 | `_filterIdentitySearchResults` | `(meta.year != null ? 1 : 0)` → `(meta.year != null ? 0 : 0)` | Assertion killed: identity year presence improves equally illustrated duplicate "2025" |
| i24 | `_filterIdentitySearchResults` | `(existing.poster != null ? 2 : 0)` → `(existing.poster != null ? 2 : 2)` | Assertion killed: identity duplicate ranking prefers poster over year in reverse order |
| i25 | `_filterIdentitySearchResults` | `(existing.year != null ? 1 : 0)` → `(existing.year != null ? 1 : 1)` | Assertion killed: identity year presence improves equally illustrated duplicate "2025" |
| i26 | `_filterIdentitySearchResults` | `(meta.poster != null ? 2 : 0)` → `(meta.poster != null ? 2 : 2)` | Assertion killed: identity duplicate ranking prefers poster over year in forward order |
| i27 | `_filterIdentitySearchResults` | `(meta.year != null ? 1 : 0)` → `(meta.year != null ? 1 : 1)` | Assertion killed: identity zero scores keep first title and original result order |
| i28 | `_filterIdentitySearchResults` | `toList(growable: false)` → `toList(growable: true)` | Equivalent E5 |
| i29 | `_normalisePosterUrl` | `url.trim().isEmpty` → `url.isEmpty` | Assertion killed: movie identity adopts without episode prompt for year "null" |
| i30 | `_normalisePosterUrl` | `return null;` → `return 'https://player.test/wrong.png';` | Assertion killed: movie identity adopts without episode prompt for year "null" |
| i31 | `_normalisePosterUrl` | `url.startsWith('//')` → `url.startsWith('/')` | Assertion killed: series identity preserves a single-slash poster URL |
| i32 | `_normalisePosterUrl` | `return 'https:$url';` → `return 'http:$url';` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i33 | `_normalisePosterUrl` | `return url;` → `return null;` | Assertion killed: series identity reuses launch episode and keeps absolute poster URL |
| i34 | `_identityMetaSubtitle` | `meta.type.toLowerCase() == 'series'` → `meta.type == 'series'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i35 | `_identityMetaSubtitle` | `? 'Series' : 'Movie'` → `? 'Movie' : 'Movie'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i36 | `_identityMetaSubtitle` | `? 'Series' : 'Movie'` → `? 'Series' : 'Series'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i37 | `_identityMetaSubtitle` | `meta.year != null && meta.year!.trim().isNotEmpty` → `meta.year != null` | Assertion killed: movie identity adopts without episode prompt for year "   " |
| i38 | `_identityMetaSubtitle` | `meta.year!,` → `'wrong-year',` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i39 | `_identityMetaSubtitle` | `meta.sourceAddon?.name.trim().isNotEmpty == true` → `meta.sourceAddon != null` | Assertion killed: movie identity adopts without episode prompt for year "null" |
| i40 | `_identityMetaSubtitle` | `meta.sourceAddon!.name` → `'wrong-addon'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i41 | `_identityMetaSubtitle` | `parts.join(' \| ')` → `parts.join(' - ')` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i42 | `_filterIdentitySearchResults` | `imdbId == null \|\| !imdbId.startsWith('tt')` → `imdbId != null && !imdbId.startsWith('tt')` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| h24 | `_pad2` | `n.toString()` → `n.toRadixString(16)` | Assertion killed: synthetic guide preserves two-digit season and episode |
| h25 | `_normalisedContentType` | `== 'series'` → `== 'movie'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i43 | `_filterIdentitySearchResults` | `'$type:$imdbId'` → `'$type$imdbId'` | Equivalent E6 |
| i44 | `_identityMetaSubtitle` | `== 'series'` → `== 'movie'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i45 | `_filterIdentitySearchResults` | `<String, StremioMeta>{}` → `<String, StremioMeta>{'injected': const StremioMeta(id: 'tt0900000', imdbId: 'tt0900000', type: 'movie', name: 'Injected')}` | Assertion killed: empty identity catalog leaves identity unset and shows empty results |
| i46 | `_filterIdentitySearchResults` | `type != 'movie'` → `type != 'film'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i47 | `_filterIdentitySearchResults` | `type != 'series'` → `type != 'tv'` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| i48 | `_filterIdentitySearchResults` | `continue;` → `break;` | Assertion killed: identity search filters and labels results then validates and accepts the season episode |
| h26 | `_generateFilenameHash` | `hashCode.toString()` → `hashCode.toRadixString(16)` | Assertion killed: fallback resume identity restores bookmark for "Plain.Movie.mkv" |
| i49 | `_filterIdentitySearchResults` | `return bestByKey.values.toList(growable: false);` → `return bestByKey.values.toList(growable: false).reversed.toList(growable: false);` | Assertion killed: identity zero scores keep first title and original result order |
| i51 | `_filterIdentitySearchResults` | `final existing = bestByKey[key];` → `final existing = bestByKey['wrong'];` | Assertion killed: identity duplicate ranking prefers poster over year in forward order |
| f01 | `_format` | `formatDuration(d)` → `d.toString()` | Assertion killed: horizontal seek HUD formats original target and signed delta |

### Equivalent variants and excluded experiments

- **E1 (s11):** persistedAudioId is read only when successReturned && persisted. The only original path setting persisted sets persistedAudioId synchronously before its first await; an unpersisted attempt never reads the initial value.
- **E2 (s12):** persistenceDone is awaited only by a successfully persisted attempt; _persistTrackChoice synchronously overwrites the initial value with its actual write completer before yielding. An unpersisted attempt never reads it.
- **E3 (i06):** The only caller normalizes a selected series then obtains BOTH season/episode from an existing pair or from the validated dialog before calling this helper. Series calls cannot have null season.
- **E4 (i07):** The same sole-caller validation ensures series calls cannot have null episode. Movie calls short circuit on contentType and never render episode suffixes.
- **E5 (i28):** The search sheet assigns the returned list, reads its length/items and iterates it. It never mutates it or exposes the list; only a selected StremioMeta leaves the sheet. Growability has no original-caller effect.
- **E6 (i43):** Keys stay injective without the colon: normalized type is exactly movie or series (distinct, non-prefix strings), followed by the unchanged IMDb id. The key remains private to this map; first-insertion/result order is unchanged.

The initial s07 constructor generator also matched `previousStremioId` and
`previousExternalPath`, producing a compile failure. That invalid run is
excluded in `sweep-invalid/s07.*`; the corrected single-field patch completes
and assertion-fails unchanged behavior tests. An s17 total+1 experiment over
both zap tests caused a paging microtask loop and was stopped/excluded in
`sweep-discarded/s17.*`. The exact same patch was then run against the unchanged
underreported-total test alone and killed its forbidden-extra-request assertion.
No test, assertion or timeout was weakened. `s17-loop-NOTE.txt` records this.

Some Flutter widget assertion failures are emitted as `print` events with a
`TestFailure`/`Expected:` block, followed by a failed `testDone`, rather than
`error.isFailure=true`. The initial progress-only classifier missed these.
`sample-classification-NOTE.txt` documents the correction: `classify.py` pairs
the raw assertion block with the actually failed test. No compile/load failure,
hang or incomplete run is counted. `sample-initial/` preserves the initial
c1/c13/c14 runs; their accepted reruns use the final two-digit guide and actual
stale mounted-menu snapshots. The final null-poster witness reruns i30; i51
also kills the map's duplicate-lookup mutation. All 31 added identities have
an individual accepted assertion witness.

### Step-0b suite baseline

At Step-0b commit `849d3b343c4d13d8db96cae2070f479317489b2c`,
`step0b-suite.jsonl` records **12,851 successes, 13 failures, 28 errors and
20 skips**. `suite_evidence.py compare --against step0-suite-isolated.jsonl`
passes: exactly 31 added successful identities, zero changed existing
outcomes, new failures, missing tests or new skips. The SDK is unchanged and
the tested tree stayed fixed throughout the run. The profile-editor identity
passes again; no allowlist is changed. The observed baseline is
`step0b-baseline-outcomes.json`, with its exact additions-only delta in
`step0b-baseline-delta.json`.

The full-suite command keeps `--no-pub` and
`--dart-define=DEBRIFY_VP_TEST_HOOKS=true`. The existing evidence-only routing
adapter supplies 114 unique isolated packages under
`.dart_tool/vplayer_parser/`, deletes 342 copied kernels, and redirects all
618 nested parse/ensure pairs. The records and audit are
`step0b/parser-routing-full-suite.jsonl` and
`step0b/parser-routing-audit.json`. The complete detached-original control
passes all 57 characterization tests (`control-complete-original.jsonl`).

Final root `flutter analyze --no-pub` retains exactly the prior 1,753
diagnostic identities/counts; scoped analysis retains all 73 S identities
with zero additions. The complete harness folder analyzes cleanly and
formats with zero changes. The seam manifest passes both current-tree and
`--at S` comparisons with zero differences. Size and architecture checks
pass. `step0b/COMMANDS-step0b.txt`, `mutation-audit.json` and `completion.json`
record commands, raw assertion verification and tested input identities.
Application code and dependency files remain byte-identical to S; Phase-1
destinations and feature-specific CI activation remain deferred to Step 1.

## Step 0b addendum — both independent samples (2026-10-11)

| Independent sample | Original revision | Original assessment | Closure |
|---|---|---|---|
| Claude sample 1 | `c502380169` (application S) | 7/17 valid kills (41%); c1 ambiguous, c15/c16 initially excluded | Step 0b systematic sweep above; unique c1 rerun; c16 exclusion refuted; 18/20 raw kills, c15 equivalent and c18 dead |
| Claude sample 2 | `849d3b343` (application S) | 9/12 valid kills (75%); d8 equivalent, d11/d12 dead | d5 and d13 now assertion-killed on the original; d1 proved caller-equivalent, no fabricated kill |

Original independent ledgers/logs remain under `claude-sample/` and
`claude-sample2/`. Sample-1 per-case initial outcomes are: c1 invalid (two matches), c2 killed, c3 killed, c4 survived, c5 killed, c6 killed, c7 survived, c8 survived, c9 survived, c10 killed, c11 killed, c12 survived, c13 survived, c14 survived, c15 survived, c16 survived, c17 killed, c18 survived, c19 survived, c20 survived. The existing 20-row rerun table records their closure.

| Second ID | Original mutation | Independent result | Addendum closure / original-caller witness |
|---|---|---|---|
| d1 | `total: math.max(total, offset + channels.length),` | survived | Equivalent: `end < max(total,end) ⇔ end < total`; merge clamps to a containing window. Existing mounted payload has total 100 below offset 100 + len 2; complete survivor run. |
| d2 | `return _IptvZapPage(` | killed | Original independent assertion kill retained; optional rerun incomplete and excluded, see NOTE. |
| d3 | `previousStremioId: _selectedStremioSubtitleId,` | killed | Assertion kill: `late embedded failure restores previous addon selection once` |
| d4 | `previousExternalPath: _activeExternalSubtitlePath,` | killed | Assertion kill: `late embedded failure restores previous addon selection once` |
| d5 | `throw const _ManualSourceValidationFailure();` | survived | Assertion kill: `manual direct source rejection restores outgoing media and position` |
| d6 | `if (season == null \|\| episode == null) return null;` | killed | Assertion kill: `series identity reuses launch episode and keeps absolute poster URL`; `series identity preserves a single-slash poster URL` |
| d7 | `if (url == null \|\| url.trim().isEmpty) return null;` | killed | Assertion kill: `movie identity adopts without episode prompt for year "null"`; `movie identity adopts without episode prompt for year "   "`; `movie identity adopts without episode prompt for year " 2025 "` |
| d8 | `if (contentType == 'series' && season != null && episode != null) {` | excluded equivalent | Equivalent: non-series identity path supplies null season and episode; remaining null guards reject the suffix. |
| d9 | `if (meta.year != null && meta.year!.trim().isNotEmpty) meta.year!,` | killed | Assertion kill: `movie identity adopts without episode prompt for year "   "` |
| d10 | `if (type != 'movie' && type != 'series') continue;` | killed | Assertion kill: `identity search filters and labels results then validates and accepts the season episode`; `identity search filters and labels results then cancels the season episode`; `identity search rejects custom series ids and keeps type namespaces`; `series identity reuses launch episode and keeps absolute poster URL`; `series identity preserves a single-slash poster URL` |
| d11 | `child: Icon(icon, color: const Color(0xFFFCA5A5), size: 20),` | excluded dead | Dead original `_RandomChoiceTile`; both constructions follow the const-true unified-menu return. Preserved by the move. |
| d12 | `onTap: onTap,` | excluded dead | Dead original `_RandomChoiceTile`; both constructions follow the const-true unified-menu return. Preserved by the move. |
| d13 | `final offset = rawOffset is num ? math.max(0, rawOffset.toInt()) : 0;` | survived | Assertion kill: `IPTV zap clamps a negative payload offset before paging` |
| d14 | `sourceId: (rawSourceId == null \|\| rawSourceId.isEmpty)` | killed | Assertion kill: `IPTV category crossing carries page category source and replacement directory`; `IPTV zap clamps a negative payload offset before paging`; `IPTV zap preserves nonzero page offsets and fetches the next page` |
| d15 | `final key = '$type:$imdbId';` | killed | Assertion kill: `identity search rejects custom series ids and keeps type namespaces` |

### Coverage and mutation additions

| Frozen declaration / caller | Added observable assertion | Original mutation proof |
|---|---|---|
| `_IptvZapPage` / `_parseIptvZapPage` → ChannelUp paging | Negative payload offset -7 produces request offset 2, bound to original source, and tunes channel 2 | d13 complete assertion failure (`Expected: <2>`, actual offset 0) |
| `_ManualSourceValidationFailure` / original mounted manual source sheet | Direct rejection logs exactly `Player: manual Stremio source rejected (_ManualSourceValidationFailure)`; all outgoing media/seek/commit rollback assertions retained | d5 complete assertion failure, captured diagnostic contains `StateError` |
| `_IptvZapPage` / every total consumer | Underreported payload retains stop/wrap behavior; backward paging reads offset only | d1 complete survivor; exhaustive caller proof in `d1-equivalence-NOTE.txt` |

The addendum adds one behavior identity and strengthens the existing direct
manual-source test. The detached original control passes all 55 behavior
tests (the three seam/reader infrastructure tests are excluded from mutation
scoring). `step0b-addendum/results.json` records exact commands, patches, test
input hashes, complete-run/compile classification and raw assertion blocks.
No production code, hook, dependencies or allowlist changed. The Step-1 gate
compares the full suite with the accepted `step0b-suite.jsonl`; only this one
additional successful identity is expected. The independent second-sample
score remains 9/12; closure kills 11/12 of its originally valid cases using
existing independent evidence plus d5/d13, with d1 now proved equivalent
(11/11 non-equivalent cases covered). Optional incomplete reruns are excluded.

## Phase 1 Step 1 — frozen moves applied (2026-10-11)

The creation commit applies the unchanged reviewed manifest (only `status`
changes from `draft` to `applied`). It classifies **893 fates: 875 retained,
16 moved and two S-patched declarations**. Current-tree ownership, token,
occurrence/binding, member-order, exact directive and scaffold checks report
zero differences against R. Whole-file format proof records five inserted
AST-optional commas, zero deleted commas and idempotence, with all other
tokens/comments/literals unchanged. Evidence: `step1/move-proof.json`,
`mechanical-unformatted/`, `current.txt` and `seam-proof.json`.

| Original declaration | Current owner / declared public name | File lines |
|---|---|---|
| `_ManualSourceValidationFailure` | `lib/features/video_player/models/vp_manual_source_validation_failure.dart` / `VpManualSourceValidationFailure` | 3 |
| `_SeasonEpisodeSelection` | `lib/features/video_player/models/vp_season_episode_selection.dart` / `VpSeasonEpisodeSelection` | 6 |
| `_SubtitleApplyAttempt` | `lib/features/video_player/models/vp_subtitle_apply_attempt.dart` / `VpSubtitleApplyAttempt` | 26 |
| `_IptvZapPage` | `lib/features/video_player/models/vp_iptv_zap_page.dart` / `VpIptvZapPage` | 24 |
| `IptvCatchupRequestGate` | `lib/features/video_player/models/iptv_catchup_request_gate.dart` / `IptvCatchupRequestGate` | 30 |
| `_VideoPlayerScreenState._diagnosticSubtitleId` | `lib/features/video_player/application/vp_subtitle_identity.dart` / `vpDiagnosticSubtitleId` | 16 |
| `_VideoPlayerScreenState._format` | `lib/features/video_player/application/vp_format.dart` / `vpFormatDuration` | 5 |
| `_VideoPlayerScreenState._pad2` | `lib/features/video_player/application/vp_format.dart` / `vpPad2` | 5 |
| `_VideoPlayerScreenState._normalisedContentType` | `lib/features/video_player/application/vp_identity_text.dart` / `vpNormalisedContentType` | 65 |
| `_VideoPlayerScreenState._subtitleSearchDisplayLabel` | `lib/features/video_player/application/vp_identity_text.dart` / `vpSubtitleSearchDisplayLabel` | 65 |
| `_VideoPlayerScreenState._filterIdentitySearchResults` | `lib/features/video_player/application/vp_identity_text.dart` / `vpFilterIdentitySearchResults` | 65 |
| `_VideoPlayerScreenState._normalisePosterUrl` | `lib/features/video_player/application/vp_identity_text.dart` / `vpNormalisePosterUrl` | 65 |
| `_VideoPlayerScreenState._identityMetaSubtitle` | `lib/features/video_player/application/vp_identity_text.dart` / `vpIdentityMetaSubtitle` | 65 |
| `_VideoPlayerScreenState._subtitlePreferenceMatchesAttempt` | `lib/features/video_player/application/vp_subtitle_identity.dart` / `vpSubtitlePreferenceMatchesAttempt` | 16 |
| `_VideoPlayerScreenState._generateFilenameHash` | `lib/features/video_player/application/vp_filename_hash.dart` / `vpFilenameHash` | 8 |
| `_RandomChoiceTile` | `lib/features/video_player/presentation/vp_random_choice_tile.dart` / `_RandomChoiceTile` | 65 |

No state ownership, resource/timer lifetime, constructor default, disposal
order, storage contract or widget tree changes. Mutable subtitle-attempt
identity/completer and catch-up generation behavior stay intact.
`IptvCatchupRequestGate` keeps its name and exact facade re-export. The private
random tile keeps its body and uses the frozen public typedef; its dead-path
coverage exception remains. Static removal is declared only for the three
reviewed top-level helpers. Every retained reference substitution is counted
by declaration, including the SeekHud duration tear-off.

### Live source tests and theme containment

| Original anchor / guard | Current anchor |
|---|---|
| Hash declaration reader / `_VideoPlayerScreenState._generateFilenameHash` | Validating reader follows S→P1 to `application/vp_filename_hash.dart::vpFilenameHash`; current body asserted, two-relocation and mutation negatives retained |
| S seam source guard | Validates the applied whole P1 ledger and separately pins the exact two S declarations / three patches / installer scaffold to S; all installation and once-only negative proofs retained |
| Manual source rejection diagnostic | Runtime expectation follows the declared `_ManualSourceValidationFailure`→`VpManualSourceValidationFailure` type rename; diagnostic template and rollback assertions unchanged; `StateError` still rejected |
| Eight other direct-source readers in rule 5 | All anchored methods remain in the facade; no anchor moved or assertion removed |
| Theme frozen paths, rendered-set route boundaries and `p2_player_dart` | All ten exact current destination paths added in the creation commit, including models/application files; exact frozen-list assertion extended |

### CI activation and checks

CI is enabled by this Step-1 commit creating the first production feature
files, including `models/vp_manual_source_validation_failure.dart`. `FEATURES`
registers `video_player` and its exact `presentation/legacy_video_player/`
bridge, rejects facade back-imports, scopes pure compatibility/type imports
by file, rejects UI/state context in pure layers and enforces a 500-line
extraction cap. The real architecture fixture accepts the production tree
and exact bridge, and rejects ten boundary/size violations. All new files
are 3–65 lines. The facade ratchet drops 18,251→18,018.

`checks.yml` adds the facade to format/analyze lists (`lib/features` already
contains all destinations), enables move checker self-test/current-tree and
scoped analyzer comparison with separate vplayer parser packages, and sets
`fetch-depth: 0`. The curated behavior list contains every characterization
file and its test-only compile-time flag; the addendum identity is in the
already registered zap file. No known-failure test allowlist changes.

The actual CI formatting scope passes: 2,321 files, zero edits. Root analysis
is 1,754 diagnostic identities/counts, with all 1,680 diagnostic occurrences outside this
slice unchanged by identity/count. Scoped comparison passes 74 diagnostics / zero additions
to the approved R/root/strict/probe inventory. Seven inventoried warnings
enter the global allowlist: six original facade warnings and the probe's
retained import warning. The global scope passes all 45 warning allowances.
The frozen import list is preserved; no warning fix or suppression is added.

Focused characterization plus theme containment: **68 successful identities**, including all 58 characterization/infrastructure tests. Commands and logs are under `step1/`; the clean-tree full suite, historical comparisons and release builds follow at the gate.

## Phase 1 clean-tree gate (2026-10-11)

The addendum is `8073fc9a2`; production/CI creation commit is
`5faaed55b0d64b33d2a84fd9f00d93af8d3c5787`. The complete gate tested that clean
commit, with no tracked or untracked changes during the suite and no tracked
changes from either release build. The final gate-record commit changes
documentation only.

| Check | Result / evidence |
|---|---|
| Full suite vs accepted Step-0b observed baseline | **PASS**: 12,852 successes, same 13 failures / 28 errors / 20 skips; exactly one additional successful identity; zero changed outcomes, missing tests, new failures or new skips. `p1-gate-suite.jsonl`, `gate/suite-comparison.txt`, `suite-delta.json` |
| Root/scoped analyzer | **PASS**: 1,754 root diagnostics, 1,680 external diagnostic occurrences, identities/counts unchanged; 74 scoped / zero additions to the approved original/strict/probe inventory. Fresh gate log and current / same-revision comparator logs |
| Format / physical size / architecture | **PASS**: actual CI scope 2,321 files / zero changes; 2,994 application/native files and 140 ratchets; 1,662 migrated files pass architecture. Facade 18,018; new files at most 65 lines |
| Existing Dart manifests | **PASS**: all 26 self-tests, exact command/exit ledger `gate/dart-selftests.json` |
| Video-player move checks | **PASS**: universal self-test, current tree, applied P1 `--at` creation commit, retained `--at T`, seam `--at S`; zero differences, same-revision inputs. `gate/ownership-checks.json` |
| Kotlin checker | **PASS**: `tvplayer_p19.json --self-test`, historical and compiled ABI/owner/snapshot negatives; exit 0. `gate/kotlin-self-test.txt` |
| Release builds | **PASS**: APK 120.56s; macOS 221.76s; both `--release --no-pub`, exit 0, tree unchanged. `gate/build-results.json`; APK / macOS ZIP and SHA-256 under `gate/artifacts/` |
| Isolated parser routing | **PASS**: 147 unique packages under `.dart_tool/vplayer_parser/`, 441 copied kernels deleted; 1247 nested parse and 1238 ensure redirects. All 31 direct manifest invocations carry the effective isolated `--parser-package`. `gate/parser-routing-audit.json` |

The profile-editor test passes at this gate; no flake rerun or test allowlist
change is needed. The baseline's 41 unsuccessful identities are retained
explicitly; the suite is parity-passing, not universally green. Existing
compiler/plugin warnings from the release builds are preserved in their
logs; no production fix or suppression is included. `gate/completion.json`
and `COMMANDS-gate.txt` pin the tested tree, SDK, input hashes, exact
commands, all results and build provenance. Application dependencies remain
unchanged from `ed728b078`.

Human checks are deferred to the end of the series and are not phase gates:
phone / Android TV with the Flutter player / tvOS / desktop should verify
random-playback menu tiles render/select, catch-up and Start Over cancellation
win over a slow lookup, identity labels remain unchanged, and a plain playlist
entry without TorBox/PikPak identifiers resumes at its saved position. No
device commands, installation, run, push, merge or branch switch occurred.
Phase 1 stops here; independent gated-range review and integration remain
with the user/Claude.

## Phase 2 Step T — original merge-base inventory (2026-10-11)

Original application revision `31a347ad2`, re-measured by declaration name:
889 exhaustive spans; 12 moved declarations (four fields, two getters, six
methods), and 14 retained reference occurrences in six declarations. The
complete draft is `dev/tool/dart_moves/vplayer_p2.json`; it is not applied.
The destination, controller/Host constructors, live adapter, eager State
constructor, `_vpSetState`, imports and declaration order are frozen. Direct
cancel-and-clear in `dispose` stays in place. All ten historical P1 destinations
are derived from the P1 manifest at the phase base and protected in the current
working tree.

The four initializers are individually inert: enum constant `SleepTimerMode.off`,
implicit `null` deadline, integer literal `0`, implicit `null` timer. The new
constructors only assign `_host`/`_s`; no Host reads, timers or service calls run
in construction. State assigns its initializer-free `late final _sleep` eagerly
in one constructor body after all original field initializers. `saveResume`
forwards zero arguments to the original `Future<void> _saveResume` (defaults
`debounced: false`, `positionOverride: null`). Context acquisitions remain
`SleepTimerSheet.show(context, …)` and `ScaffoldMessenger.of(context)`; the moved
code has no builder-local context. Counts: mounted 3, context 2, setState 3.

Owner-scoped bare field access is an explicit per-field binding opt-in, restricted
to the field's exact destination file and controller. Binding-only real-config
negatives reject another physical class, a same-named local, an owned field
through `_host`, a wrong owner declaration, and an attempted declared Host
binding. The opt-in also rejects globally disabling or class-narrowing mandatory
qualification; the capture fixture keeps occurrence counts equal on both sides. Removing the opt-in restores mandatory qualification. Existing manifest
behavior is preserved. Analyzer mapping now derives P1 identities from historical
manifests as well as the current P2 manifest; it cannot lose P1 mappings on the CI
transition.

Evidence under `<git-common-dir>/refactor-evidence/vplayer/p2/tooling/`:
`probe/remeasured.json`, `construction-and-inventory.json`, complete raw/formatted
materializations, `optional-commas.json`, `format-diagnostics.json`, analyzer
logs and `async-context-identities.json`. The formatted split compares with zero
differences, is idempotent, inserts/deletes zero optional commas and introduces
zero diagnostics. Original root: 74 scoped occurrences; byte-identical strict
original: 141; complete compiling receiver/rename probe: 75. Maximum inventory:
142 occurrences across 34 identities, preserving P1 maxima. The sole probe delta
is the destination's `directives_ordering` info. All three original
`use_build_context_synchronously` declaration identities and their counts remain
unchanged (`_switchToSourcePlaylist`: 1, `_toggleRecording`: 4, `build`: 1).

CI current-tree/analyzer selection stays at P1 until the production creation
commit switches it to P2 and adds P1 `--at 31a347ad2`. The strengthened, validating
EOF sleep-anchor retarget and theme path additions belong to that creation
commit. Application code, app dependencies and size baseline are unchanged.

## Phase 2 Step 0 — original sleep-timer characterization (2026-10-11)

Application original: `31a347ad2`; no production moves or new seams. Twenty-one
behavior tests mount and dispose the original deterministically. Calls use the
public Controls/TvControls, unified menu and channel-guide callbacks, player
events and existing preference transport; no test accesses private State.
The storage barrier suspends the real `_saveResume`, not a replacement helper.
All 21 new tests have assertion-failing original mutation witnesses using the
final frozen test/support inputs. Both controls layouts assert the sleep label;
desktop uses the configured styled dock tooltip and TV uses its rendered text.

The sweep enumerates **81** statement/branch/literal points across all 12 moved
declarations and 14 retained reference occurrences: **68/68 reachable
non-equivalent mutations assertion-killed**, **9 caller-equivalent**, **4
platform/clock pending**. One pending mobile-intent mutation was executed and
survived the complete macOS control; it is not classified as equivalent.
Compilation failures and uncaught exceptions earn no kill credit. First-pass
logs and input snapshots remain in `step0/campaign-v1/`, `campaign-v2/` and
`characterization-inputs/`; all accepted results are in `mutation-results.json`.
The ledger pins each run's input hashes: 52 valid kills used earlier campaign
inputs, and 16 final-input mutation reruns provide assertion-failing witnesses
for all 21 final tests. The final control and full suite use the committed inputs.
An independent Claude sample remains the next review checkpoint.

### Behavior coverage and final-input mutation witnesses

| ID | Original caller behavior | Assertion-failing mutation(s) |
|---|---|---|
| C01 | sleep menu and desktop dock preserve mode, preset and ceil label | `g-round` |
| C02 | sleep menu and TV dock preserve mode, preset and ceil label | `g-round` |
| C03 | selection callback immediately rebuilds countdown menu and dock | `g-round`, `r11-menu-mode` |
| C04 | selection callback immediately rebuilds endOfItem menu and dock | `r11-menu-mode` |
| C05 | off callback immediately rebuilds an armed menu and dock | `cancel-render` |
| C06 | off cancels countdown and clears mode, preset and dock label | `cancel-native` |
| C07 | re-arm replaces old countdown and fires only at the new expiry | `start-cancel` |
| C08 | end-of-item cancels countdown and EOF stops before playlist advance | `cancel-native` |
| C09 | end-of-item EOF returns before Xtream series channel advance | `eof-return` |
| C10 | IPTV live menu gates end-of-item through the original caller | `live-menu-gate`, `dispose-nullguard` |
| C11 | IPTV VOD menu gates end-of-item through the original caller | `live-menu-gate`, `dispose-nullguard` |
| C12 | disposal cancels the armed countdown without firing later | `r05-dispose-cancel` |
| C13 | expiry awaits the real resume write before pause and clears the timer | `fire-save` |
| C14 | expiry awaits native pause before displaying its toast | `fire-pause-await` |
| C15 | in-flight expiry after dispose still calls disposed pause and reports its error without toast | `fire-late-pause` |
| C16 | in-flight expiry after dispose suppresses toast when native pause succeeds | `fire-late-pause`, `toast-mounted` |
| C17 | late overlapping EOF after disposal clears end mode before the next callback | `cancel-unmounted-mode` |
| C18 | sleep latch cancels an already queued automatic adjacent episode | `fire-latch` |
| C19 | sleep latch outranks a pending live IPTV recovery retry | `fire-latch` |
| C20 | sleep latch blocks further recovery after an in-flight live open completes late | `fire-latch` |
| C21 | end-of-item carried from VOD to live blocks recovery without treating live EOF as completion | `r01-recovery-mode` |

### Per-declaration coverage matrix

Lines are AST declaration starts at the merge base, measured by name; attached
comments start earlier. T inventories the exact frozen token spans separately.

| Original declaration (line) | Caller coverage / boundary | Sweep points |
|---|---|---|
| `_iptvRecoveryEligible` (683) | C19–C21: latch and carried end-mode reject recovery (1 site) | `r01-recovery-mode` |
| `_sleepTimerMode` (1454) | C01–C04, C10–C11: default and selected menu modes | `f-mode`, `f-mode-countdown` |
| `_sleepTimerDeadline` (1456) | C01–C04, C07, C13: null default masked by off; arm/ceil/expiry | `f-deadline` |
| `_sleepTimerArmedMinutes` (1461) | C01–C07, C13: zero default, preset and reset | `f-preset` |
| `_sleepTimer` (1464) | C06–C09, C12–C16: cancellation, replacement and suspended expiry | `f-timer` |
| `_onPlaybackEnded` (5207) | C08–C09, C17, C21: end-mode/cancel/toast before advance and overlapping late EOF (3 sites) | `r02-eof-mode`, `r03-eof-cancel`, `r04-eof-toast`, `eof-latch`, `eof-return` |
| `dispose` (11857) | C12, C15–C16: direct timer cancel/clear and in-flight fire (2 sites) | `r05-dispose-cancel`, `r06-dispose-clear`, `dispose-nullguard` |
| `_buildTvControls` (13054) | C02: TV callback and rendered label (2 sites) | `r07-tv-callback`, `r08-tv-label` |
| `_sleepTimerMinutesLeft` (13812) | C01–C07, C13: zero/ceil menu arguments; real decrement pending | `g-mode`, `g-null`, `g-off-zero`, `g-unit`, `g-edge`, `g-negative`, `g-denominator`, `g-round` |
| `_sleepTimerButtonLabel` (13823) | C01–C08: null / Episode / N min in controls and dock | `label-off`, `label-episode`, `label-count`, `label-remaining` |
| `_showSleepTimerSheet` (13830) | C01–C04, C10–C11: unified sleep section; legacy tail dead | `menu-section`, `menu-return`, `menu-unified` |
| `_applySleepTimerSelection` (13851) | C01–C11: real row and captured selection callbacks, all modes | `select-off-cancel`, `select-off-toast`, `select-minutes`, `select-end-cancel`, `select-end-render`, `select-end-mode`, `select-end-toast` |
| `_startSleepCountdown` (13865) | C01–C07, C12–C19: arm, replace, cancellation and expiry | `start-cancel`, `start-duration`, `start-render`, `start-mode`, `start-deadline`, `start-preset`, `start-store`, `start-callback`, `start-toast` |
| `_cancelSleepTimer` (13877) | C05–C09, C12–C17: mounted cancellation and disposed overlapping EOF | `cancel-native`, `cancel-clear`, `cancel-off-check`, `cancel-off-return`, `cancel-mounted`, `cancel-off-mode`, `cancel-deadline`, `cancel-preset`, `cancel-unmounted-mode`, `cancel-unmounted-deadline`, `cancel-nullguard`, `cancel-render` |
| `_fireSleepTimer` (13893) | C13–C19: save/pause order, latch, suspended save/pause; replacement pending | `fire-cancel`, `fire-latch`, `fire-wanted`, `fire-created`, `fire-no-player`, `fire-save`, `fire-await`, `fire-pause`, `fire-late-pause`, `fire-toast`, `fire-pause-await` |
| `_showSleepTimerToast` (13906) | C01–C09, C13–C16: exact text, duration, behavior and mounted guard | `toast-mounted`, `toast-behavior`, `toast-duration`, `toast-content` |
| `build` (14721) | C01: desktop callback and styled dock label (2 sites) | `r09-desktop-callback`, `r10-desktop-label` |
| `_buildPlayerMenuPanel` (17005) | C01–C11, C13: mode/preset/minutes/callback (4 sites) | `r11-menu-mode`, `r12-menu-preset`, `r13-menu-left`, `r14-menu-selection`, `live-menu-gate` |

### Systematic mutation table

Every row mutates one exact, uniquely contextualized occurrence in the original
declaration. Raw replacement strings, offsets, commands, hashes and assertion
messages are in `step0/points.json` and `mutation-results.json`.

| Point | Original declaration | Result / evidence or equivalence reason |
|---|---|---|
| `f-mode` | `_sleepTimerMode` | Assertion-killed: C01, C02 |
| `f-deadline` | `_sleepTimerDeadline` | Equivalent: Off mode masks the deadline; every countdown overwrites it before any read. No timer reads it while off/end-of-item. |
| `f-preset` | `_sleepTimerArmedMinutes` | Assertion-killed: C01, C02, C04 |
| `f-timer` | `_sleepTimer` | Equivalent: Explicit null equals Dart implicit null; no branch/literal other than null exists in this initializer. T independently freezes inert initialization. |
| `g-mode` | `_sleepTimerMinutesLeft` | Assertion-killed: C01, C02, C03 |
| `g-null` | `_sleepTimerMinutesLeft` | Equivalent: Every public countdown arm sets a nonnull deadline synchronously with its mode; every clear first changes the mode to off. No reachable countdown-null state exists. The valid mutation preserves Dart flow analysis using a forced null check. |
| `g-off-zero` | `_sleepTimerMinutesLeft` | Assertion-killed: C01, C02, C04 |
| `g-unit` | `_sleepTimerMinutesLeft` | Assertion-killed: C01, C02, C03 |
| `g-edge` | `_sleepTimerMinutesLeft` | Equivalent: At zero the fall-through ceil(0/60000) is also zero; negatives still return zero. |
| `g-negative` | `_sleepTimerMinutesLeft` | Pending: Real DateTime.now is not intercepted by fake_async. Nonpositive real remaining with a still-armed timer requires the approved wall-clock/device check. |
| `g-denominator` | `_sleepTimerMinutesLeft` | Assertion-killed: C01, C02, C03 |
| `g-round` | `_sleepTimerMinutesLeft` | Assertion-killed: C01, C02, C03 |
| `label-off` | `_sleepTimerButtonLabel` | Assertion-killed: C01, C02 |
| `label-episode` | `_sleepTimerButtonLabel` | Assertion-killed: C04 |
| `label-count` | `_sleepTimerButtonLabel` | Assertion-killed: C01, C02, C03 |
| `label-remaining` | `_sleepTimerButtonLabel` | Pending: Ceil of real remaining initially equals armed minutes. The real countdown decrement is explicitly device-pending in the approved plan. |
| `menu-section` | `_showSleepTimerSheet` | Assertion-killed: C01, C02 |
| `menu-return` | `_showSleepTimerSheet` | Assertion-killed: C01, C02 |
| `select-off-cancel` | `_applySleepTimerSelection` | Assertion-killed: C06 |
| `select-off-toast` | `_applySleepTimerSelection` | Assertion-killed: C06 |
| `select-minutes` | `_applySleepTimerSelection` | Assertion-killed: C01, C02, C07 |
| `select-end-cancel` | `_applySleepTimerSelection` | Assertion-killed: C08 |
| `select-end-render` | `_applySleepTimerSelection` | Assertion-killed: C04 |
| `select-end-mode` | `_applySleepTimerSelection` | Assertion-killed: C04, C08 |
| `select-end-toast` | `_applySleepTimerSelection` | Assertion-killed: C08 |
| `start-cancel` | `_startSleepCountdown` | Assertion-killed: C07 |
| `start-duration` | `_startSleepCountdown` | Assertion-killed: C01, C02, C07 |
| `start-render` | `_startSleepCountdown` | Assertion-killed: C03 |
| `start-mode` | `_startSleepCountdown` | Assertion-killed: C01, C02, C07 |
| `start-deadline` | `_startSleepCountdown` | Assertion-killed: C01, C02 |
| `start-preset` | `_startSleepCountdown` | Assertion-killed: C01, C02, C07 |
| `start-store` | `_startSleepCountdown` | Assertion-killed: C07, C12 |
| `start-callback` | `_startSleepCountdown` | Assertion-killed: C07 |
| `start-toast` | `_startSleepCountdown` | Assertion-killed: C01, C02 |
| `cancel-native` | `_cancelSleepTimer` | Assertion-killed: C06, C08 |
| `cancel-clear` | `_cancelSleepTimer` | Equivalent: All stored timers are cancelled first. Repeated cancel is idempotent; next arm overwrites it and dispose cancels it again. No caller inspects timer identity. |
| `cancel-off-check` | `_cancelSleepTimer` | Assertion-killed: C06, C08 |
| `cancel-off-return` | `_cancelSleepTimer` | Equivalent: When off, initial/default or completed cancellation already has null deadline and zero preset; reassigning identical values cannot change public menu/dock/player/timer behavior. |
| `cancel-mounted` | `_cancelSleepTimer` | Assertion-killed: C06, C08 |
| `cancel-off-mode` | `_cancelSleepTimer` | Assertion-killed: C06, C08 |
| `cancel-deadline` | `_cancelSleepTimer` | Equivalent: Getter returns zero while off; next countdown overwrites deadline. Deadline is private and has no other readers. |
| `cancel-preset` | `_cancelSleepTimer` | Assertion-killed: C06, C08 |
| `cancel-unmounted-mode` | `_cancelSleepTimer` | Assertion-killed: C17 |
| `cancel-unmounted-deadline` | `_cancelSleepTimer` | Equivalent: Disposed cancellation can be reached by a late EOF, but its deadline has no readers: mode is off, no mounted menu exists, and next countdown cannot run. The overlapping EOF reads mode only. |
| `fire-cancel` | `_fireSleepTimer` | Assertion-killed: C13 |
| `fire-latch` | `_fireSleepTimer` | Assertion-killed: C18, C19, C20 |
| `fire-wanted` | `_fireSleepTimer` | Pending: Survives all original macOS callers. Functional reads are Android-only renderer fallback and Android/iOS openingStartOver background handling; the other reads only snapshot/restore. No raw Platform seam is authorized; not claimed equivalent. |
| `fire-created` | `_fireSleepTimer` | Assertion-killed: C13 |
| `fire-no-player` | `_fireSleepTimer` | Pending: Only initial setup before controls or Android-only in-place replacement can leave playerCreated false; no new Platform seam is authorized. |
| `fire-save` | `_fireSleepTimer` | Assertion-killed: C13 |
| `fire-await` | `_fireSleepTimer` | Assertion-killed: C13 |
| `fire-pause` | `_fireSleepTimer` | Assertion-killed: C13 |
| `fire-late-pause` | `_fireSleepTimer` | Assertion-killed: C15, C16 |
| `fire-toast` | `_fireSleepTimer` | Assertion-killed: C13 |
| `toast-mounted` | `_showSleepTimerToast` | Assertion-killed: C16 |
| `toast-behavior` | `_showSleepTimerToast` | Assertion-killed: C13 |
| `toast-duration` | `_showSleepTimerToast` | Assertion-killed: C13 |
| `r01-recovery-mode` | `_iptvRecoveryEligible` | Assertion-killed: C21 |
| `r02-eof-mode` | `_onPlaybackEnded` | Assertion-killed: C08 |
| `r03-eof-cancel` | `_onPlaybackEnded` | Assertion-killed: C08 |
| `r04-eof-toast` | `_onPlaybackEnded` | Assertion-killed: C08 |
| `r05-dispose-cancel` | `dispose` | Assertion-killed: C12 |
| `r06-dispose-clear` | `dispose` | Equivalent: After direct timer cancellation disposal removes every subsequent timer reader; clearing only drops the dead reference. T freezes its statement position. |
| `r07-tv-callback` | `_buildTvControls` | Assertion-killed: C02 |
| `r08-tv-label` | `_buildTvControls` | Assertion-killed: C02 |
| `r09-desktop-callback` | `build` | Assertion-killed: C01 |
| `r10-desktop-label` | `build` | Assertion-killed: C01 |
| `r11-menu-mode` | `_buildPlayerMenuPanel` | Assertion-killed: C03, C04 |
| `r12-menu-preset` | `_buildPlayerMenuPanel` | Assertion-killed: C03 |
| `r13-menu-left` | `_buildPlayerMenuPanel` | Assertion-killed: C03 |
| `r14-menu-selection` | `_buildPlayerMenuPanel` | Assertion-killed: C03, C04 |
| `eof-latch` | `_onPlaybackEnded` | Assertion-killed: C08 |
| `eof-return` | `_onPlaybackEnded` | Assertion-killed: C09 |
| `live-menu-gate` | `_buildPlayerMenuPanel` | Assertion-killed: C10, C11 |
| `f-mode-countdown` | `_sleepTimerMode` | Assertion-killed: C01, C02 |
| `menu-unified` | `_showSleepTimerSheet` | Assertion-killed: C01, C02 |
| `cancel-nullguard` | `_cancelSleepTimer` | Assertion-killed: C06, C08, C16 |
| `dispose-nullguard` | `dispose` | Assertion-killed: C10, C11 |
| `fire-pause-await` | `_fireSleepTimer` | Assertion-killed: C14 |
| `toast-content` | `_showSleepTimerToast` | Assertion-killed: C13 |
| `cancel-render` | `_cancelSleepTimer` | Assertion-killed: C05 |

### Dead paths, existing races and pending platform checks

`kUnifiedPlayerMenuEnabled` is constant true. The unified branch, exact sleep
section and early return are exercised; the legacy sheet tail is dead:
hide-timer cancellation, `SleepTimerSheet.show` arguments, mounted check,
auto-hide, nullable picked result and legacy apply callback. These are retained
verbatim in the manifest; no production flag or source-text behavior test was
added to manufacture execution. The cancel method's unmounted assignments
are reached by overlapping EOFs suspended in completion storage during
disposal. The first clears end mode; the second enters the legacy next-episode
lookup after disposal. The mode write is observable and mutation-killed; its
deadline remains private and has no later countdown or mounted UI reader.

**Existing race outcomes, preserved:** after disposal while save is blocked,
releasing it still invokes the disposed player's pause. A fake native rejection
is propagated as `StateError`; a successful late pause emits no toast. A live
recovery open already issued with `play: true` can finish after the sleep pause
and set the fake player playing again; the latch blocks subsequent recovery.
This records the existing call-order contract under a delayed open completion,
not a claim that a real native platform has been exercised. No bug was fixed.

**Pending:** real wall-clock countdown decrement and nonpositive-remaining
branch (approved design); Android player-instance replacement while save is
suspended, including `playerCreated == false` and pause on the replacement
instance; Android/iOS playback-intent consumers. The only in-place replacement
caller is `_fallbackExplicitRendererToAutomatic`, whose eligibility uses raw
`Platform.isAndroid`; `_pauseForBackground` also gates on raw Android/iOS.
`debugDefaultTargetPlatformOverride` cannot change either. No platform seam,
emulator, device command or private-State invocation was introduced.

The existing P1 clean-tree suite baseline is reusable: `5faaed55b` and
`31a347ad2` have identical application, original tests, dependencies and root
analysis configuration, with identical Flutter 3.44.8 / Dart 3.12.2 SDK.
`step0/base-suite-reuse.json` pins the equality command and original observed
13 failures / 28 errors / 20 skips. The new full-suite baseline runs on the
clean characterization/tooling checkpoint and compares identities for additions only;
no allowlist or dependency change. CI list registration and P2 manifest/analyzer
selection remain in the production creation commit, as specified by Step T.
All harness commands include `--dart-define=DEBRIFY_VP_TEST_HOOKS=true`.

### Clean-tree Step 0 baseline and compatibility checks

Characterization commit `61fac9315`; qualification-default compatibility
correction and final tested checkpoint `5b2b62c3b`. The first suite exposed an
existing IPTV checker fixture's single textual default-anchor requirement.
The shared guard now evaluates that default once; unchanged default-false/true
fixture assertions pass. The first run remains archived under `suite-attempt1/`;
no failure was allowlisted or accepted as the new baseline.

`step0-suite-final.jsonl` and its environment record pin a clean, unchanged tree,
Flutter 3.44.8 / Dart 3.12.2, and **12,873 successes / 13 failures / 28 errors /
20 skips**. Against the reusable P1 observed gate, there are **21 added passing
identities**, zero missing or changed original identities, zero new failures
and zero new skips. Both the strict identity ledger (`step0/suite-delta.json`)
and official comparison (`step0/suite-comparison.txt`) pass. This is the new
observed suite baseline for the later production move.

All 26 existing Dart manifest self-tests, the P2 universal/real-config tests and
889-span original self-comparison, and P1 `--at 31a347ad2` pass after the fix.
`step0/compat-checks-effective.json` records queued and effective commands;
the draft P2 self-test explicitly uses `--self-compare-original`. The parser
audit records 309 unique isolated wrapper packages, 927 copied kernels deleted,
and explicit manifest flags; nested hard-coded parser requests use the isolated
package too. The successful Step T Kotlin historical/compiled self-test is
reused: checker, partitioner, fixture/manifests and native application inputs
are unchanged. Hashes and commands are in `step0/completion.json`.

Format, changed-test analysis, size and architecture checks pass. Root analysis
has 1,770 diagnostics versus the observed P1 gate's 1,754: tracked-source
identities/multiplicities are unchanged; the 16 additions are path warnings in
ignored Android/macOS release-build copies of `pubspec.yaml`, preserved and
documented in `step0/root-analyzer-delta.json`. The scoped video-player comparator
and diagnostic negatives pass with 74 occurrences and zero additions.
Platform/clock limitations above remain pending; no production move, new seam,
CI transition, application/dependency change or bug fix is included.

## Phase 2 Step 0b addendum — independent original sample (2026-10-11)

Claude sampled the original application at `61fac9315`, using all 76
video-player characterization tests. Evidence is in `p2/claude-sample/`:
`p2-claude-muts.json`, `p2-claude-run.log`, `results.json` and per-mutation
logs. Eighteen of 21 compile-valid mutations were assertion-killed. Excluding
`e2` (zero falls through to `ceil(0) == 0`) gives the reported **18/20 = 90%**,
meeting the independent-sample threshold. The remaining two were audited
before extraction; neither is silently counted as a kill.

| Sample | Original declaration / change | Original outcome / resolution |
|---|---|---|
| `e1` | Exact mutation in sample manifest | Assertion-killed: C01, C02, C03 |
| `e2` | minutes-left `<= 0` → `< 0` | Equivalent: `remaining == 0` returns zero either way (sweep `g-edge`). |
| `e3` | Exact mutation in sample manifest | Assertion-killed: C04, C08 |
| `e4` | Exact mutation in sample manifest | Assertion-killed: C01, C02, C03 |
| `e5` | Exact mutation in sample manifest | Assertion-killed: C10, C21 |
| `e6` | Exact mutation in sample manifest | Assertion-killed: C05, C06 |
| `e7` | Exact mutation in sample manifest | Assertion-killed: C08 |
| `e8` | Exact mutation in sample manifest | Assertion-killed: C07 |
| `e9` | Exact mutation in sample manifest | Assertion-killed: C01, C02, C03, C05 |
| `e10` | Exact mutation in sample manifest | Assertion-killed: C07 |
| `e11` | cancel off-mode early return removed | Caller-equivalent: off invariant and identical-value `setState`, as detailed below (sweep `cancel-off-return`). |
| `e12` | Exact mutation in sample manifest | Assertion-killed: C05, C06, C07, C08 |
| `e13` | Exact mutation in sample manifest | Assertion-killed: C18, C19, C20 |
| `e14` | fire playback-intent write deleted | Device-pending: mobile playback intent, as detailed below (sweep `fire-wanted`; not equivalent). |
| `e15` | Exact mutation in sample manifest | Assertion-killed: C13, C15, C16 |
| `e16` | Exact mutation in sample manifest | Assertion-killed: C13, C07, C14, C18 |
| `e17` | Exact mutation in sample manifest | Assertion-killed: C13 |
| `e18` | Exact mutation in sample manifest | Assertion-killed: C21 |
| `e19` | Exact mutation in sample manifest | Assertion-killed: C01, C02, C03, C12 |
| `e20` | Exact mutation in sample manifest | Assertion-killed: C01, C02, C03, C05 |
| `e21` | Exact mutation in sample manifest | Assertion-killed: C01, C02 |

**`e11` equivalence.** Both versions cancel and clear the timer before the
return. While mounted, off mode implies null deadline and zero armed minutes:
initializers start there; cancellation resets all three together; arming sets
countdown/deadline/preset together; end-mode selection first cancels. Removing
the return only adds `setState` assigning the same values. Subsequent selection,
arming and toast work runs in the same synchronous caller stack; menu, dock,
player calls, writes and timers are identical. After disposal the same
mode/deadline values are reassigned, without changing the retained preset.
The performance cost of redundant invalidation is not a behavior-test kill.

**`e14` pending evidence.** All 11 occurrences of `_activeMediaShouldPlay`
were inventoried in `step0b/survivor-analysis.json`. Functional reads are
renderer fallback (`_fallbackExplicitRendererToAutomatic`, 4321), guarded by
raw `Platform.isAndroid`, and opening Start Over/background handling
(`_pauseForBackground`, 11796), guarded by raw Android/iOS. Fallback's resume
predicate also requires `!_sleepStopLatched`, so the latch alone rejects resume
immediately after a sleep stop. The remaining read (10505) snapshots the value
for rejection rollback at 10527; it adds no independent player/UI effect.
The mobile intent write remains preserved and **device-pending**, not equivalent.
No raw Platform seam or private-State access is introduced to force coverage.

Exact `e11` and `e14` mutations and an original control were rerun with all
76 public-caller characterization tests in the detached original evidence
worktree, nice 19, serialized, hook flag true; all three runs pass and restore
original source. Commands/results: `step0b/runs.json`. No new tests were needed
for the proven-equivalent point; the device-only point remains a listed limit.
The addendum changes documentation/evidence only, so the accepted clean
`step0-suite-final.jsonl` at `5b2b62c3b` remains the observed **step-0b baseline**,
with zero additions, identical test/application/dependency inputs and SDK.

## Phase 2 Step 1 — applied sleep-timer ownership (2026-10-11)

Follows step-0b addendum `5205111eb`. Applied P2 manifest retains all 889
original fates, moves exactly 12 declarations, qualifies exactly 14 retained
reference sites, and derives/protects all ten P1 destinations from history.
Production files are byte-identical to the accepted Step T formatted
materialization: zero further formatting edits, zero optional-comma changes
and zero formatting-introduced diagnostics. Original comments remain attached.

| Original State member | Current controller member |
|---|---|
| `_sleepTimerMode` | `VpSleepTimerController.sleepTimerMode` |
| `_sleepTimerDeadline` | `VpSleepTimerController.sleepTimerDeadline` |
| `_sleepTimerArmedMinutes` | `VpSleepTimerController.sleepTimerArmedMinutes` |
| `_sleepTimer` | `VpSleepTimerController.sleepTimer` |
| `_sleepTimerMinutesLeft` | `VpSleepTimerController.sleepTimerMinutesLeft` |
| `_sleepTimerButtonLabel` | `VpSleepTimerController.sleepTimerButtonLabel` |
| `_showSleepTimerSheet` | `VpSleepTimerController.showSleepTimerSheet` |
| `_applySleepTimerSelection` | `VpSleepTimerController.applySleepTimerSelection` |
| `_startSleepCountdown` | `VpSleepTimerController.startSleepCountdown` |
| `_cancelSleepTimer` | `VpSleepTimerController.cancelSleepTimer` |
| `_fireSleepTimer` | `VpSleepTimerController.fireSleepTimer` |
| `_showSleepTimerToast` | `VpSleepTimerController.showSleepTimerToast` |

Destination: `presentation/legacy_video_player/vp_sleep_timer_controller.dart`
(149 lines). Its constructor stores the narrow 12-member Host; all four owned
initializers are inert. State eagerly assigns its initializer-free `late final
_sleep` in one constructor body, after original field initialization and before
`initState`. The adapter has live one-line forwarders; `_vpSetState` preserves
protected State ownership. Dispose keeps direct timer cancel/clear at the exact
original statement position. Shared latch/player/playback-intent fields stay
State-owned, and every original timing, callback, toast and save/pause order stays.

### Source guards, CI and boundaries

| Guard | Original anchor / selection | Current proof |
|---|---|---|
| `player_auto_next_routing_test.dart` | Whole-facade sections; sleep `indexOf` could return -1 | Five named current declarations from validating reader; `_sleep.sleepTimerMode == SleepTimerMode.endOfItem` and fetch anchors explicitly non-negative; original relative-order and routing assertions retained |
| EOF sleep branch negatives | Missing/reordered sleep branch | Both actual retargeted tests assertion-fail in detached evidence materialization; validating reader refuses edited live text (`step1/source-mutation-results.json`), no historical-text fallback |
| Seam source proof | Current-tree P1 ledger | Latest applied ownership (P2); original S interception patches still pinned through P1 ledger, current installer tokens directly equal frozen S; all original installation/default/negative assertions retained |
| Theme containment | P1 destination paths | New exact destination in surface manifest, rendered route boundaries, frozen path list and both exact expected lists in source guard |

CI selects P2 for self-test/current-tree and analyzer, explicitly chooses the P2
inventory preserving P1 identities, and adds P1 `--at 31a347ad2` with its own
parser package. Full-history checkout remains enabled. Both sleep-test files
join `ci_behavior_tests.txt`; harness commands retain the test-hook define.
Existing `lib/features` format/analyze scopes cover the new destination. Exact
bridge registration, facade back-import ban, pure-layer boundaries and 500-line
extraction cap remain active and all architecture negatives pass.

Facade size ratchet lowers **18,018 → 17,932**; the new controller is 149 lines.
The dated size note retains prior phase notes and names remaining phases 3–25.
No application change outside the two frozen production files, dependency
change, warning-allowlist addition, clock/platform seam or bug fix is included.
The architecture fixture tool now honors `VPLAYER_EVIDENCE_ROOT` (legacy default
unchanged). Its initial P1 temporary copy auto-removed; the accepted rerun writes
only under P2. No persistent P1 artifact was overwritten.

Before commit: 92 affected tests pass (79 video-player, three routing, ten theme
source guards); current ownership zero differences; scoped analyzer/self-tests
75 diagnostics/zero additions; exact CI analyzer allowlist 45 pre-existing
warnings/nothing new or stale; format, size, architecture and seam negatives pass.
Commands and hashes: `p2/step1/completion.json`. Device/clock/sample dispositions
from Step 0/0b remain unchanged. Clean-tree full-suite/build gate follows.

## Phase 2 clean-tree gate (2026-10-11)

Step-0b addendum `5205111eb`; production creation and tested clean tree
`b0533aac5`. The accepted baseline remains `step0-suite-final.jsonl` at
`5b2b62c3b` (Step 0b changes no test/application inputs). The complete gate
suite is `p2-gate-suite.jsonl`; environment pins Flutter 3.44.8 / Dart 3.12.2,
clean creation revision and no tree changes during the run.

| Check | Observed result / evidence |
|---|---|
| Full suite by identity | 12,873 successes / 13 failures / 28 errors / 20 skips; zero added, missing, changed or newly failing/skipped identities; strict equality and official helper PASS (`gate/suite-delta.json`, `suite-comparison.txt`) |
| Move/history | P2 current tree, universal/real-config self-test and same-revision `--at b0533aac5` zero differences; P1 historical `--at 31a347ad2` PASS; all ten earlier destinations protected |
| Dart precedent checks | All 26 existing manifest self-tests PASS with explicit isolated parser-package flags (`gate/accepted-checks.json`) |
| Kotlin precedent | Complete historical/compiled self-test PASS in the P2 evidence root; initial interrupted invocation excluded (`gate/kotlin-result.json`, `kotlin-self-p2.log`) |
| Analyzer | P2 comparator including infos and identity/multiplicity negatives: 75 scoped, zero additions; CI warning allowlist: 45 pre-existing, nothing new/stale |
| Root analyzer identities | 1,770 → 1,771: only the frozen destination directives-ordering info from T; every non-video-player identity/multiplicity unchanged. Existing 16 ignored build-pubspec path warnings remain unsuppressed (`gate/root-analyzer-delta.json`) |
| Format / size / architecture | PASS; controller 149, facade 17,932; 2,995 files / 140 ratchets; 1,663 migrated files; bridge/import/cap negatives pass |
| Release APK | `nice -n 19 flutter build apk --release --no-pub`: PASS, 114.31 s, APK 102,268,046 bytes |
| Release macOS | `nice -n 19 flutter build macos --release --no-pub`: PASS, 108.77 s; app launcher and Dart AOT hashes recorded |

Both builds ran sequentially after the suite, without install/run, and left the
tracked tree clean and pubspec unchanged. Artifact paths/flags/hashes are in
`gate/build-results.json`. Every harness suite uses the test-hook define;
release builds use the normal default path. No device/emulator commands.

Parser routing audit: 496 unique isolated wrapper packages, 1,467 copied kernels
deleted, 96 explicit manifest invocations; seven detached-worktree copies were
already kernel-clean before wrapping. Nested legacy parser requests route to
the isolated package (`gate/parser-routing-audit.json`).

**Evidence-routing deviations, corrected:** the initial architecture self-test
used its legacy P1 temporary path and cleaned the copy automatically; the tool
now honors the phase root, with accepted rerun under P2. The first Kotlin gate
invocation omitted `TVPLAYER_EVIDENCE_ROOT` and used the legacy TV-player root;
it was interrupted on discovery and earns no credit. Complete rerun with explicit
`p2/kotlin` root passed. Raw batch retains the interrupted row and therefore exits
nonzero; the accepted 30-command ledger replaces only that row with the successful
rerun. Both attempts/notes remain under P2; no prior source/test evidence deleted.

`gate/completion.json` pins all results and constraints. Existing race outcomes
and `e14` remain preserved; real-clock decrement/nonpositive branch, Android
replacement/player-created-false during a blocked resume save, and mobile
Start Over/background intent remain device-pending. End-of-series phone,
Android TV Flutter player, tvOS and desktop checklist remains pending.
No further production moves or bug fixes included; stop at the Phase 2 gate.


## Phase 3 tooling checkpoint (2026-10-11)

Original `fc24e32ae`, approved design `de55d9987`: 882 exhaustive spans,
17 moved declarations and 17 retained references (14 substitutions + three
unchanged notifier reads/cleanup). The full raw and formatted virtual split
compares with zero differences. The draft, generator and real-configuration
negatives are checked in; production application and pubspec remain unchanged.

The existing State constructor is patched to preserve `_sleep` then eagerly
assign `_skip`. Ten relocated initializers are individually inert: two false
literals, static-const provider id and empty segments, three implicit nulls,
zero generation, empty map and true media-ready. Constructors store references
only; no Host reads before widget/context assignment. `_activeSkipSegmentUi`
keeps its original State allocation slot. Exact Host: 19 names / 20 declarations,
live getter/setter for position, computed State forwarders, existing `_vpSetState`.
Formatted destination: 260 lines; it exists only in evidence.

All 26 precedent Dart manifests, universal/P3 real configuration, P1 historical
`--at 31a347ad2`, P2 historical `--at fc24e32ae`, and complete Kotlin
historical/compiled self-test pass. The new configuration proves map accesses,
nullable record selectors, generation increments, position writes, retained
constructor assignment, Host signatures and all 11 earlier destinations.
Initial invalid no-op constructor negative is retained in raw evidence; corrected
complete universal rerun passes. Shared comparison/binding behavior is unchanged.

Analyzer original root/strict/raw/formatted: 75/142/78/81 scoped occurrences;
P1/P2 mappings preserved, maxima frozen, async-context declaration identities
unchanged. Formatting inserts/deletes zero optional commas and is idempotent;
three brace infos are exposed by formatted longer receiver statements in
`_currentSkipSegmentRequest` (one) and `_syncSkipSegmentsForCurrentContent`
(two), archived without rewriting code. Comparator/negative tests report zero
additions. Size/architecture pass. Commands/results and parser audit:
`p3/tooling/completion.json`, `accepted-checks.json`, `parser-audit.json`.

CI remains on applied P2. The P3 creation commit must change both current/self
commands and analyzer manifest/inventory, retain P1 at `31a347ad2` and P2 at
`fc24e32ae`, register new characterization files and extend all three theme lists.
No production move, new seam, bug fix, dependency change or device command.


## Phase 3 original characterization checkpoint (2026-10-11)

Application base `fc24e32ae` re-measured by declaration name; Step T
`c1d4cb51b`, characterization `55ac577e6`. **No production moves or CI
transition.** All 58 new behavior tests pass on the original with the existing
H1 seam. The original application,
pubspec and analyzer allowlists are unchanged. Every new test has an
assertion-failing original mutation with the final test-input hashes.

The six `video_player_skip_*_test.dart` files cover requests/settings,
identity/key partitioning, playlist/media boundaries, fetch/profile races and
tracker ordering. `support/skip_segment_driver.dart` drives public controls,
player streams, rendered notifier/clock contracts and held HTTP responses;
`skip_settings_reads.dart` holds the existing preferences transport. The
existing HTTP fixture records client close and optionally aborts held requests.
It adds no application seam. All commands use nice 19, no pub resolution,
serialized Flutter processes and `DEBRIFY_VP_TEST_HOOKS=true`.

**Pinned original outcomes.** Older A→B→A success/error writes cache before
generation rejection and clears loading by key alone. A late old completion
can poison a future cache return while the newest displayed result stays
intact, including a newest error. Returning to cached A does not increment
generation: the current-key guard must keep a held B completion from clearing
A's UI. An outgoing mounted route accepts its held result after profile
handoff; disposal rejects publication; an incoming route independently loads
its disabled/provider settings. ProfilePolicyGuard and profile cache resets
mirror the existing handoff. These gaps remain in Follow-ups.

Playlist tests cover the positive outgoing-clock interval after transition
completion but before an incoming duration, zero-duration rejection,
failed-load re-arm, same-key/no-frame detours and cache preservation. They
observe the skip notifier cleared **before** the new-media clock notification.
The independent engine boundary clears source-switch UI. A suspended native
seek publishes clock/position and clears UI before completion; disposal saves
the target position. Subsecond shortening within one whole-second key retains
the existing visible-button quirk after a clamped seek.

Seek order is observed as clock → native seek → synchronous MDBList queue →
haptic, with all three tracker targets pinned. HTTP stops arrive Simkl,
Trakt, MDBList because their preparation differs. A second skip back below
80% re-arms the two periodic checkpoints at the same fake time: the existing
heartbeat diagnostics prove Trakt before Simkl and kill the source-call swap.
TV Select dispatches skip while controls are hidden, with explicit seek count
and no pause. Teardown drains timers through normal production disposal.

### Phase 3 coverage matrix — all 17 moved declarations

Ten relocated initializer proofs are also frozen individually at T; the
State-owned notifier allocation remains at its original slot. The following
references identify runtime witnesses or the precise equivalent/default fate.

| Declaration at base | Line | Coverage / initializer proof | Sweep points |
|---|---:|---|---|
| `_skipSegmentSettingsLoaded` | 1285 | false literal; loader store before provider use | f-loaded, settings-loaded-store, request-loaded |
| `_skipSegmentsEnabled` | 1286 | false literal; enabled/disabled settings and provider gating | f-enabled, settings-enabled-*, request-enabled |
| `_skipSegmentProviderId` | 1287 | static const auto; configured provider transport and key namespace | f-provider-id, settings-provider-*, settings-id-store |
| `_skipSegmentProvider` | 1288 | implicit null; creation, configured transport, normal/aborted close | f-null-_skipSegmentProvider, settings-provider-store, r11-dispose-close |
| `_skipSegments` | 1289 | static const empty; successful/error/cache publication and active UI | f-segments, success-segments, error-segments, sync-cache-segments |
| `_loadedSkipSegmentsKey` | 1290 | implicit null; stale-key UI and same-key reset/late cache writes | f-null-_loadedSkipSegmentsKey, *-loaded-key, reset-loaded |
| `_loadingSkipSegmentsKey` | 1291 | implicit null; exact-key dedupe and A/B/A vs different-key completion | f-null-_loadingSkipSegmentsKey, sync-loading*, complete-*, reset-loading |
| `_skipSegmentsFetchGeneration` | 1292 | zero literal; relative counter identity; stale success/error/reset/dispose | f-generation, sync-generation, *-generation |
| `_skipSegmentsCache` | 1293 | empty map allocation, no callbacks; cached episode/key return and stale writes | f-cache, *-cache*, reset-cache-clear |
| `_skipSegmentsMediaReady` | 1304 | true literal; positive duration re-arm, failed load and transition-finished window | f-media-ready, request-media-ready, reset-media-ready, r04, r08 |
| `_loadSkipSegmentSettings` | 1714 | C36 | settings-*; dormant replacement / web fallback classified below |
| `_currentSkipSegmentRequest` | 1788 | C05, C37, C38, C39, C40, C41, C42, C43, C44, C45, C46, C47, C48, C49, C50 | request-*; independent IMDb/season/episode/duration key partitioning |
| `_syncSkipSegmentsForCurrentContent` | 1854 | C22, C23, C33, C34, C35 | sync-*, success-*, error-*, complete-*; all three profile outcomes |
| `_resetSkipSegmentState` | 1917 | C01, C03, C04, C11, C12 | reset-*; held reset, no-frame detour, cache return, notifier/clock order |
| `_activeSkipSegment` | 1932 | C51 | active-*; loaded key and exact segment start/end |
| `_syncActiveSkipSegmentUi` | 1938 | C08 | ui-update, r03, r06, r07, r16; visible label and notifier contract |
| `_skipActiveSegment` | 1942 | C52 | action-*; clamp/suspended seek/tracker heartbeat/TV; player-created false device-pending |

### Retained-reference matrix — all 17 occurrences

Fourteen substitutions are drafted; r07/r13/r16 deliberately retain the
State notifier. Disposal generation/close/null remain individual statements
at their original positions. Exact source substitutions remain frozen even
when one statement is observationally redundant.

| Point | Original caller / line | Planned fate | Runtime witness / disposition |
|---|---|---|---|
| `r01-init` | `initState`:1668 | declared substitution | C36 |
| `r02-position-sync` | `_bindPlayerInstanceSubscriptions`:3815 | declared substitution | C13 |
| `r03-position-ui` | `_bindPlayerInstanceSubscriptions`:3816 | declared substitution | C51 |
| `r04-duration-ready` | `_bindPlayerInstanceSubscriptions`:3861 | declared substitution | C01, C11 |
| `r05-duration-sync` | `_bindPlayerInstanceSubscriptions`:3862 | declared substitution | C51, C54 |
| `r06-duration-ui` | `_bindPlayerInstanceSubscriptions`:3863 | declared substitution | C51 |
| `r07-media-clear` | `_beginMediaGeneration`:4665 | unchanged notifier | C08 |
| `r08-failure-ready` | `_clearTransitionOnFailure`:10459 | declared substitution | C02 |
| `r09-playlist-reset` | `_loadPlaylistIndexAttempt`:10651 | declared substitution | C11, C12 |
| `r10-dispose-generation` | `dispose`:11954 | declared substitution | E20 |
| `r11-dispose-close` | `dispose`:11955 | declared substitution | C28, C29, C31 |
| `r12-dispose-null` | `dispose`:11956 | declared substitution | E21 |
| `r13-notifier-dispose` | `dispose`:11998 | unchanged notifier | C10 |
| `r14-tv-active` | `_handleTvKey`:13315 | declared substitution | C53 |
| `r15-tv-action` | `_handleTvKey`:13316 | declared substitution | C53 |
| `r16-build-listenable` | `build`:15527 | unchanged notifier | C36, C52 |
| `r17-build-action` | `build`:15560 | declared substitution | C52 |

### Systematic mutation table

148 statement/branch/literal points cover the entire moved list and all
retained occurrences: **119 assertion kills, 26 equivalents, three classified
paths**. Every executed point compiles and finishes; no timeout, compilation
failure or exception without an assertion earns a kill. Exact before/after
text, offsets, patches, commands, completed identities, assertion text and
input hashes are in `p3/step0/points.json`, `mutation-results.json` and
`mutations/`. `coverage.json` indexes the final 58-test witnesses.

The first systematic pass (51 tests) is preserved in `campaign-v1/`: 100
assertion kills, zero compilation failures. Its narrow source-literal file
selection missed dynamic test names; the final runner always discovers all
six files. All real survivors were replayed and closed with original-caller
tests. TV missing-seek exceptions earned no credit until explicit count
assertions killed both mutations. An initial expanded-control callback used
guarded `expect` inside an async pump; recording values and asserting after
the awaited pump corrected the test. All attempts remain in evidence.
This is our systematic sweep; Claude's independent P3 sample is pending.

| Point | Base line | Result | Witness / disposition |
|---|---:|---|---|
| `f-loaded` | 1285 | EQUIVALENT | E01 |
| `f-enabled` | 1286 | EQUIVALENT | E02 |
| `f-provider-id` | 1287 | EQUIVALENT | E03 |
| `f-null-_skipSegmentProvider` | 1288 | EQUIVALENT | E04 |
| `f-null-_loadedSkipSegmentsKey` | 1290 | EQUIVALENT | E05 |
| `f-null-_loadingSkipSegmentsKey` | 1291 | EQUIVALENT | E06 |
| `f-segments` | 1289 | EQUIVALENT | E07 |
| `f-generation` | 1292 | EQUIVALENT | E08 |
| `f-cache` | 1293 | KILL | C08, C09, C17 … |
| `f-media-ready` | 1304 | EQUIVALENT | E09 |
| `settings-enabled-read` | 1716 | KILL | C36, C56 |
| `settings-provider-read` | 1717 | KILL | C36 |
| `settings-mounted` | 1719 | KILL | C55 |
| `settings-enabled-value` | 1721 | KILL | C02, C05, C06 … |
| `settings-provider-value` | 1722 | KILL | C56 |
| `settings-available` | 1723 | KILL | C56 |
| `settings-provider-create` | 1728 | KILL | C36, C56 |
| `settings-create-id` | 1729 | KILL | C36 |
| `settings-enabled-store` | 1731 | KILL | C36, C56 |
| `settings-id-store` | 1732 | EQUIVALENT | E10 |
| `settings-loaded-store` | 1733 | KILL | C36, C56 |
| `settings-sync` | 1734 | EQUIVALENT | E11 |
| `settings-close` | 1727 | DORMANT | Only initState calls loader; initial provider is null. Replacement is not reachable. |
| `request-custom` | 1790 | KILL | C14 |
| `request-loaded` | 1805 | EQUIVALENT | E12 |
| `request-enabled` | 1806 | EQUIVALENT | E13 |
| `request-media-ready` | 1807 | KILL | C01 |
| `request-transition` | 1808 | KILL | C08 |
| `request-duration` | 1809 | KILL | C51 |
| `request-catalog-series` | 1815 | KILL | C36, C39 |
| `request-playlist-series` | 1815 | KILL | C05 |
| `request-series-return` | 1816 | KILL | C39 |
| `request-id-trim` | 1818 | KILL | C48, C49 |
| `request-id-first-regex` | 1819 | KILL | C05 |
| `request-id-fallback` | 1820 | KILL | C13 |
| `request-id-fallback-trim` | 1820 | KILL | C13 |
| `request-id-final-regex` | 1822 | KILL | C13 |
| `request-playlist-season-branch` | 1826 | KILL | C01, C05 |
| `request-playlist-season` | 1828 | KILL | C01, C05 |
| `request-playlist-episode` | 1829 | KILL | C01, C05 |
| `request-effective-season` | 1831 | KILL | C15, C16 |
| `request-effective-episode` | 1832 | KILL | C15 |
| `request-parse-branch` | 1833 | KILL | C16 |
| `request-parse-season` | 1835 | KILL | C50 |
| `request-parse-episode` | 1836 | KILL | C50 |
| `request-season-negative` | 1838 | KILL | C48 |
| `request-episode-zero` | 1838 | KILL | C43 |
| `request-key-seconds` | 1842 | KILL | C54 |
| `request-record-imdbId` | 1846 | KILL | C05, C36 |
| `request-record-season` | 1847 | KILL | C05, C36 |
| `request-record-episode` | 1848 | KILL | C05, C36 |
| `request-record-duration` | 1849 | KILL | C05, C36 |
| `request-key-imdbId` | 1844 | KILL | C17 |
| `request-key-season` | 1844 | KILL | C18 |
| `request-key-episode` | 1844 | KILL | C19 |
| `request-key-durationSeconds` | 1844 | KILL | C51, C54 |
| `sync-provider-null` | 1857 | EQUIVALENT | E14 |
| `sync-loaded` | 1858 | KILL | C33, C34 |
| `sync-loading` | 1859 | KILL | C22, C23, C33 … |
| `sync-cache-branch` | 1863 | KILL | C20, C21 |
| `sync-cache-value` | 1864 | KILL | C20, C21 |
| `sync-cache-mounted` | 1865 | KILL | C20, C21 |
| `sync-cache-segments` | 1867 | KILL | C20, C21 |
| `sync-cache-key` | 1868 | KILL | C20, C21 |
| `sync-cache-ui` | 1870 | EQUIVALENT | E15 |
| `sync-generation` | 1875 | KILL | C22, C33, C34 |
| `sync-loading-store` | 1876 | KILL | C22, C23, C33 … |
| `sync-fetch-imdbId` | 1879 | KILL | C36 |
| `sync-fetch-season` | 1880 | KILL | C36 |
| `sync-fetch-episode` | 1881 | KILL | C36 |
| `sync-fetch-duration` | 1882 | KILL | C36 |
| `success-cache` | 1885 | KILL | C20, C21 |
| `success-mounted` | 1886 | EQUIVALENT | E16 |
| `success-generation` | 1886 | KILL | C22, C33 |
| `success-key` | 1887 | KILL | C25 |
| `success-segments` | 1889 | KILL | C01, C02, C03 … |
| `success-loaded-key` | 1890 | KILL | C33, C34, C36 |
| `success-ui` | 1892 | KILL | C22, C33, C34 … |
| `error-cache` | 1898 | KILL | C23, C24 |
| `error-log` | 1900 | KILL | C23, C24, C29 |
| `error-mounted` | 1902 | EQUIVALENT | E17 |
| `error-generation` | 1902 | KILL | C34 |
| `error-segments` | 1905 | KILL | C27 |
| `error-key` | 1903 | KILL | C26 |
| `error-loaded-key` | 1906 | KILL | C35 |
| `error-ui` | 1908 | EQUIVALENT | E18 |
| `complete-samekey` | 1911 | KILL | C22, C33 |
| `complete-clear` | 1912 | KILL | C22, C33 |
| `reset-generation` | 1924 | KILL | C12 |
| `reset-loading` | 1925 | KILL | C11 |
| `reset-loaded` | 1926 | KILL | C04 |
| `reset-segments` | 1927 | EQUIVALENT | E19 |
| `reset-media-ready` | 1928 | KILL | C01, C03, C04 |
| `reset-ui` | 1929 | KILL | C01 |
| `active-key` | 1934 | KILL | C51 |
| `active-position` | 1935 | KILL | C36, C51 |
| `ui-update` | 1939 | KILL | C36, C51 |
| `action-guard` | 1944 | KILL | C52, C57 |
| `action-player-created` | 1944 | DEVICE PENDING | Only Android renderer replacement can make playerCreated false while a retained skip callback exists. No raw platform seam authorized. |
| `action-clamp` | 1945 | KILL | C07 |
| `action-target` | 1947 | KILL | C52, C57 |
| `action-position` | 1948 | KILL | C09 |
| `action-clock` | 1949 | KILL | C52, C57 |
| `action-clock-immediate` | 1949 | KILL | C52, C57 |
| `action-ui` | 1950 | KILL | C09 |
| `action-seek` | 1951 | KILL | C57 |
| `action-trakt` | 1952 | KILL | C57 |
| `action-simkl` | 1953 | KILL | C57 |
| `action-mdblist` | 1954 | KILL | C57 |
| `action-haptic` | 1955 | KILL | C52 |
| `action-order` | 1952 | KILL | C58 |
| `r01-init` | 1668 | KILL | C36 |
| `r02-position-sync` | 3815 | KILL | C13 |
| `r03-position-ui` | 3816 | KILL | C51 |
| `r04-duration-ready` | 3861 | KILL | C01, C11 |
| `r05-duration-sync` | 3862 | KILL | C51, C54 |
| `r06-duration-ui` | 3863 | KILL | C51 |
| `r07-media-clear` | 4665 | KILL | C08 |
| `r08-failure-ready` | 10459 | KILL | C02 |
| `r09-playlist-reset` | 10651 | KILL | C11, C12 |
| `r10-dispose-generation` | 11954 | EQUIVALENT | E20 |
| `r11-dispose-close` | 11955 | KILL | C28, C29, C31 |
| `r12-dispose-null` | 11956 | EQUIVALENT | E21 |
| `r13-notifier-dispose` | 11998 | KILL | C10 |
| `r14-tv-active` | 13315 | KILL | C53 |
| `r15-tv-action` | 13316 | KILL | C53 |
| `r16-build-listenable` | 15527 | KILL | C36, C52 |
| `r17-build-action` | 15560 | KILL | C52 |
| `request-season-rejection` | 1838 | KILL | C42 |
| `request-episode-rejection` | 1838 | KILL | C43, C44 |
| `request-missing-season` | 1835 | KILL | C45 |
| `request-missing-episode` | 1836 | KILL | C46 |
| `request-season-local` | 1824 | KILL | C36 |
| `request-episode-local` | 1825 | KILL | C36 |
| `request-key-record` | 1850 | KILL | C17, C18, C19 … |
| `sync-cache-return` | 1872 | KILL | C20, C21 |
| `sync-render-0` | 1866 | EQUIVALENT | E22 |
| `sync-render-1` | 1888 | EQUIVALENT | E23 |
| `sync-render-2` | 1904 | EQUIVALENT | E24 |
| `settings-provider-store` | 1728 | KILL | C36, C56 |
| `complete-unconditional` | 1911 | KILL | C21 |
| `reset-cache-clear` | 1924 | KILL | C03, C04 |
| `action-duration-positive` | 1945 | EQUIVALENT | E25 |
| `request-key-provider-prefix` | 1844 | EQUIVALENT | E26 |
| `request-custom-accept` | 1790 | KILL | C14, C38 |
| `request-id-fallback-accept` | 1820 | KILL | C05, C13, C40 … |
| `request-parse-defaults` | 1834 | KILL | C15, C16, C45 … |
| `settings-web-fallback` | 1725 | WEB PENDING | Storage normalizes unknown ids on native; unavailable persisted provider can only reach this branch on web. No platform seam added. |

### Equivalent-point proof notes

These are source/caller arguments backed by full original characterization
replays (51 tests at the first pass; 58 for the two additional points), not
equivalence inferred solely from a passing test. Removing `setState` preserves
the same assignments and notifier publication; these fields have no other
rendering consumer. The settings loader is started before initialization,
shares the cached SharedPreferences future, and performs its two reads before
the sequential player-default reads finish. It cannot reload within a State.
Dispose returns before the provider's asynchronous completion handler executes,
so mounted and generation each independently reject late publication.

| Disposition | Point | Proof |
|---|---|---|
| E01 | `f-loaded` | Settings loader runs before any player subscription; it sets all values before sync. A false flag is otherwise only read before settings/provider exist. |
| E02 | `f-enabled` | Overwritten by settings before provider construction can be consumed; unloaded guard masks the initial value. |
| E03 | `f-provider-id` | Overwritten by load before any request. |
| E04 | `f-null-_skipSegmentProvider` | Dart implicit null equals explicit null; no allocation/effect. |
| E05 | `f-null-_loadedSkipSegmentsKey` | Dart implicit null equals explicit null; no allocation/effect. |
| E06 | `f-null-_loadingSkipSegmentsKey` | Dart implicit null equals explicit null; no allocation/effect. |
| E07 | `f-segments` | Same immutable empty content before a key is loaded. |
| E08 | `f-generation` | Only relative generation equality is read; absolute starting value is not observable. |
| E09 | `f-media-ready` | No positive duration exists before first real duration event, which assigns true before sync. |
| E10 | `settings-id-store` | Provider never changes during the session. A consistent noncolliding key prefix affects neither query nor cache partitioning. |
| E11 | `settings-sync` | Loader precedes first duration in current original construction; duration/position callers immediately synchronize afterward. |
| E12 | `request-loaded` | Settings is read before initialization creates player subscriptions; before that provider/duration also gate. Held preferences test pins unloaded behavior. |
| E13 | `request-enabled` | Disabled load creates no provider and there is no session settings reload or loaded disabled cache; provider-null path masks it. |
| E14 | `sync-provider-null` | Settings enabled implies provider nonnull; disabled/unloaded request null; disposal cancels subscriptions before nulling provider. |
| E15 | `sync-cache-ui` | Both stream callers immediately sync UI after this synchronous cache branch; loader runs before a positive duration exists. |
| E16 | `success-mounted` | Dispose always increments fetch generation before nulling provider; generation guard independently rejects every post-disposal completion. Removing the mounted term alone is redundant. |
| E17 | `error-mounted` | Dispose always increments fetch generation before nulling provider; generation guard independently rejects every post-disposal completion. Removing the mounted term alone is redundant. |
| E18 | `error-ui` | All initiating stream callers already clear UI for a new unmatched key. Empty error cannot introduce a segment; subsequent tick repeats clear. |
| E19 | `reset-segments` | Loaded-key/media-ready guards hide outgoing segments; every successful/cache/error publication overwrites them before assigning the new loaded key. |
| E20 | `r10-dispose-generation` | Mounted guard independently rejects every late completion; cache dies with State and callbacks are cancelled. Exact statement remains frozen by move proof. |
| E21 | `r12-dispose-null` | No subscription callback survives current-instance guard; closed provider never reused, State inaccessible after disposal. |
| E22 | `sync-render-0` | Skip rendering is owned by the notifier and both callers refresh it independently. Only an otherwise identical facade rebuild is omitted; the full original replay passes. |
| E23 | `sync-render-1` | Skip rendering is owned by the notifier and both callers refresh it independently. Only an otherwise identical facade rebuild is omitted; the full original replay passes. |
| E24 | `sync-render-2` | Skip rendering is owned by the notifier and both callers refresh it independently. Only an otherwise identical facade rebuild is omitted; the full original replay passes. |
| E25 | `action-duration-positive` | The active getter only returns a segment when its request has positive duration; no await intervenes before this read. |
| E26 | `request-key-provider-prefix` | Provider is loaded once per State; replacing its constant per-session key namespace cannot collide with another provider during that State lifetime. |

Provider replacement is **dormant**, with `initState` the only loader caller
and an initially null provider. Native storage normalizes unknown ids to auto
(executable case recorded); actual unavailable-provider fallback is
**web-pending**. A false player-created flag with an extant skip callback
requires Android renderer replacement and is **device-pending**. No platform
predicate seam or production hook was added. End-of-series phone, Android TV
Flutter player, tvOS and desktop skip-button/Select/episode-switch checklist
remains pending.

### Each new test's final-input assertion witness

All 58 pass in the detached `fc24e32ae` control. Each row below selects a
mutation run with exactly the final characterization input hashes, done event,
successful compilation and a TestFailure for that identity. The full witness
list and assertions are archived, including additional witnesses per test.

| Case | Original-caller test identity | Mutation witness |
|---|---|---|
| C01 | skip playlist episode wins over launch arguments and switches wait for real duration | `request-media-ready` |
| C02 | skip failed playlist load re-arms prior current media without a duration event | `settings-enabled-value` |
| C03 | skip playlist reset preserves cached episode on return | `success-segments` |
| C04 | skip playlist reset reloads same-key cache after no-frame detour | `success-segments` |
| C05 | skip request falls back to guide IMDb and accepts series playlist without catalog type | `settings-enabled-value` |
| C06 | skip unknown persisted provider normalizes to auto before settings load | `settings-enabled-value` |
| C07 | skip clamps to subsecond duration using the same whole-second request key | `success-segments` |
| C08 | skip engine media boundary clears UI on direct source change independently of playlist reset | `settings-enabled-value` |
| C09 | skip suspended native seek immediately clears UI and disposal saves target position | `settings-enabled-value` |
| C10 | skip notifier borrowed by rendered builder is disposed with its State owner | `r13-notifier-dispose` |
| C11 | skip playlist held A-B-A reset loading permits new same-key request | `settings-enabled-value` |
| C12 | skip playlist held A-B-A reset generation survives failed-load re-arm | `settings-enabled-value` |
| C13 | skip rejects invalid guide IMDb before using valid trimmed fallback | `settings-enabled-value` |
| C14 | skip custom launch identity prevents request even when guide later has IMDb | `request-custom-accept` |
| C15 | skip channel effective identity wins over launch and parsed metadata | `success-segments` |
| C16 | skip channel effective identity fills only missing parsed episode | `success-segments` |
| C17 | skip cache key independently partitions channel IMDb | `settings-enabled-value` |
| C18 | skip cache key independently partitions channel season | `settings-enabled-value` |
| C19 | skip cache key independently partitions channel episode | `settings-enabled-value` |
| C20 | skip cache returns episode-duration key without another fetch | `success-segments` |
| C21 | skip stale generation caches result without publishing wrong duration | `success-segments` |
| C22 | skip held A-B-A old success caches and clears same-key loading before generation rejection | `settings-enabled-value` |
| C23 | skip held A-B-A old error caches and clears same-key loading before generation rejection | `settings-enabled-value` |
| C24 | skip failed fetch caches empty and logs once without retrying ticks | `success-segments` |
| C25 | skip current cached A stays visible when held B completes with success in the same generation | `success-key` |
| C26 | skip current cached A stays visible when held B completes with error in the same generation | `success-segments` |
| C27 | skip failed changed-key fetch clears previously loaded segments | `success-segments` |
| C28 | skip provider closes on disposal and late success cannot publish | `settings-enabled-value` |
| C29 | skip close-aborted fetch logs once without publishing or uncaught errors | `settings-enabled-value` |
| C30 | skip outgoing mounted route publishes held result after profile changes as-is | `success-segments` |
| C31 | skip outgoing disposed route rejects held result after profile changes | `settings-enabled-value` |
| C32 | skip incoming route reads incoming disabled settings and provider independently | `settings-enabled-value` |
| C33 | skip held A-B-A late old success preserves newer UI but poisons cache as-is | `success-segments` |
| C34 | skip held A-B-A late old error preserves newer UI but poisons cache as-is | `success-segments` |
| C35 | skip held A-B-A current error remains displayed after late old success until cache return | `error-loaded-key` |
| C36 | skip settings enable one exact request and position ticks deduplicate it | `settings-enabled-value` |
| C37 | skip request rejects disabled | `settings-enabled-value` |
| C38 | skip request rejects custom identity | `request-custom-accept` |
| C39 | skip request rejects non-series | `request-catalog-series` |
| C40 | skip request rejects invalid IMDb | `request-id-fallback-accept` |
| C41 | skip request rejects missing IMDb | `request-id-fallback-accept` |
| C42 | skip request rejects negative season | `request-season-rejection` |
| C43 | skip request rejects zero episode | `request-episode-rejection` |
| C44 | skip request rejects negative episode | `request-episode-rejection` |
| C45 | skip request rejects missing season | `request-parse-defaults` |
| C46 | skip request rejects missing episode | `request-parse-defaults` |
| C47 | skip request rejects missing season episode | `request-parse-defaults` |
| C48 | skip request preserves season 0 and trims IMDb | `settings-enabled-value` |
| C49 | skip request preserves season 7 and trims IMDb | `settings-enabled-value` |
| C50 | skip request falls back to parsed title season and episode | `settings-enabled-value` |
| C51 | skip button uses loaded duration key and exact segment boundaries | `success-segments` |
| C52 | skip action seeks and publishes clock immediately before native completion and haptic | `settings-enabled-value` |
| C53 | TV Select owns visible skip action while the bar is hidden | `settings-enabled-value` |
| C54 | skip exact key distinguishes adjacent whole seconds while subsecond ticks share it | `settings-enabled-value` |
| C55 | skip unloaded settings start no request and disposed settings completion creates no provider | `settings-mounted` |
| C56 | skip configured single-provider choice reaches IntroDB rather than auto or SkipDB | `settings-enabled-value` |
| C57 | skip publishes clock before seek, queues tracking before haptic and preserves remote stop order | `settings-enabled-value` |
| C58 | skip tracker seek order arms Trakt heartbeat before Simkl | `action-order` |

Root analyzer remains 1,771 identities/occurrences, zero additions/removals
versus the reusable P2 gate; changed tests analyze cleanly. Original application,
dependency/configuration and pre-existing test inputs at `fc24e32ae` are
identical to the clean P2 gate `b0533aac5`; `baseline-reuse.json` records SDK,
revision and hashes. The clean-tree additions-only full-suite baseline is
recorded below with its tested revision.
CI stays on P2 until the production creation commit, which must register all
six new test files and perform the exact P3 transition documented above.

## Phase 3 clean original baseline (2026-10-12)

Tested clean characterization revision `55ac577e6`, original application
`fc24e32ae`. Complete run `p3/step0-suite-final.jsonl` pins Flutter 3.44.8 /
Dart 3.12.2, hook define, no pub resolution and unchanged tree during the run.
The accepted reusable baseline is `p2/p2-gate-suite.jsonl` at clean
`b0533aac5`, with original application/dependency/configuration/test inputs
verified identical at the phase base.

| Check | Result / evidence |
|---|---|
| Full suite | 12,931 successes / 13 failures / 28 errors / 20 skips; exactly 58 added passing identities, every pre-existing identity/outcome unchanged (`step0/suite-delta.json`) |
| Official comparison | PASS, zero new failures, missing, newly skipped or fixed identities (`step0/suite-comparison.txt`); no allowlist additions |
| Original mutation control | All 58 pass; all 58 have final-input assertion witnesses; 148 points = 119 killed / 26 equivalent / three classified (`step0/coverage.json`) |
| Analyzer | 1,771 before/after by identity/multiplicity; zero additions/removals; changed tests clean (`analyzer-checkpoint-delta.json`, `test-analyze-post-control.log`) |
| Format / boundaries | PASS; 2,995 files / 140 size ratchets; 1,663 migrated files; no baseline raise or production changes |
| Parser routing | 185 unique isolated invocation packages / 555 copied kernels deleted / 32 explicit manifest invocations; 2,488 nested routes; all under `.dart_tool/vplayer_parser/` (`step0/parser-routing-audit.json`) |

Step T's complete precedent self-tests/historical checks, analyzer probe and
materialization remain valid; only tests/support/docs changed at Step 0.
The slow final IPTV settings fixture self-test completed successfully with
isolated parser packages. No overlapping Flutter suites or application builds.
`step0/completion.json` ties the results to revisions, input hashes and hard
constraints. CI remains P2, P3 manifest draft. Independent Claude P3 sample,
web-unavailable-provider and Android player-created-false paths, plus the
end-of-series device checklist, remain pending. Stop before production moves.


## Phase 3 Step-0b addendum — independent sample (2026-10-12)

Claude's sample on original `55ac577e6` kills 20/21 (95.2%). The
f9–f13/f20 COMPILE-ERR labels were heuristic false positives (test names
containing "loading"); all 134 tests executed. Saved per-mutation logs contain
only their last 20 KB and omit the assertion sections. Complete serialized
replays on the detached original (application byte-identical to `55ac577e6`)
confirm assertion kills for all six, with no compilation/load errors:
`p3/addendum/replay-results.json`, full `f*.jsonl`/stderr. Original Claude
artifacts remain untouched; corrected table in `claude-normalized.json`.

| Mutation | Correct outcome | Assertion witness / equivalence |
|---|---|---|
| f1 | killed | `skip configured single-provider choice reaches IntroDB rather than auto or SkipDB` |
| f2 | equivalent original-caller startup ordering | `f2-equivalence.json` |
| f3 | killed | `skip custom launch identity prevents request even when guide later has IMDb` |
| f4 | killed | `skip playlist episode wins over launch arguments and switches wait for real duration` |
| f5 | killed | `skip engine media boundary clears UI on direct source change independently of playlist reset` |
| f6 | killed | `skip rejects invalid guide IMDb before using valid trimmed fallback` |
| f7 | killed | `skip request falls back to guide IMDb and accepts series playlist without catalog type` |
| f8 | killed | `skip request preserves season 0 and trims IMDb` |
| f9 | killed | `skip cache returns episode-duration key without another fetch` |
| f10 | killed | `skip playlist episode wins over launch arguments and switches wait for real duration` |
| f11 | killed | `skip playlist reset preserves cached episode on return` |
| f12 | killed | `skip playlist held A-B-A reset generation survives failed-load re-arm` |
| f13 | killed | `skip held A-B-A old error caches and clears same-key loading before generation rejection` |
| f14 | killed | `skip stale generation caches result without publishing wrong duration` |
| f15 | killed | `skip playlist episode wins over launch arguments and switches wait for real duration` |
| f16 | killed | `skip cache returns episode-duration key without another fetch` |
| f17 | killed | `skip clamps to subsecond duration using the same whole-second request key` |
| f18 | killed | `skip publishes clock before seek, queues tracking before haptic and preserves remote stop order` |
| f19 | killed | `skip publishes clock before seek, queues tracking before haptic and preserves remote stop order` |
| f20 | killed | `skip playlist episode wins over launch arguments and switches wait for real duration` |
| f21 | killed | `skip provider closes on disposal and late success cannot publish` |

**f2 is equivalent through the original callers, strengthening sweep E11
(`settings-sync`), not a missing late-settings test.** Only `initState` calls
this loader, before `_initializePlayer`. Both skip settings reads await
`ProfilePreferences.instance` → the same cached `SharedPreferences.getInstance`
completer; all per-key reads/guards after it are synchronous. Player
initialization awaits `_loadPlayerDefaults`, whose first three unconditional
preferences reads follow that same path sequentially. The skip reads register
first; their `Future.wait` completion hop precedes the later defaults await
hops, on both cold and warm caches. Duration initializes to zero and its only
positive assignment is in subscriptions installed after defaults and player
creation; decoder replacement sets it to zero. At the trailing sync, request
construction therefore rejects zero duration before any fetch/state/notifier
write. Pausing and synchronous first frames do not change that ordering.
Disposal returns earlier; errors leave before this statement in both versions.
Profile read guards add no async per-key delay. A private reload, bypassed
initialization or new settings seam would manufacture a different caller.
`f2-equivalence.json` records the exact original/dependency hashes and complete
argument. The f2 removal replay passes all 134 original behavior tests.

The systematic sweep remains 148 points: 119 assertion kills, 26 equivalents
(E11 now substantiated), three classified paths. The independent sample is
20/21 raw, 20/20 after this equivalent exclusion. No new test or behavior
change is needed; keep the trailing sync in the frozen production move.
Coverage matrix for `_loadSkipSegmentSettings`: C36/C55/C56 and the existing
settings witnesses unchanged; its trailing sync is E11/f2-equivalent.
The clean `55ac577e6` additions-only suite is the Step-0b baseline unchanged
(`addendum/baseline-reuse.json`); no allowlist additions.


## Phase 3 Step 1 — applied frozen split (2026-10-12)

Creation commit follows addendum `682d86812`. Application changes are the
facade and `presentation/legacy_video_player/vp_skip_segment_controller.dart`
only: 17 moved declarations, one patched constructor, 14 substituted retained
occurrences and three unchanged State notifier references. The 260-line
controller/Host and computed adapter are the Step T formatted materialization
byte for byte (`step1/materialization-application.json`); 882 exhaustive fates
compare with zero differences. Every initializer's inertness proof and the
State-owned notifier allocation proof remain `tooling/construction-proof.json`.
Sleep constructs first, skip second, with no Host reads at construction.
Dispose's generation/close/null statements stay separately at their original
positions. No behavior, race, profile or schema changes.

CI current/self-test and both analyzer arguments now select P3. P1 remains
`--at 31a347ad2`; P2 adds `--at fc24e32ae`. Six behavior files are registered,
hook define remains enabled for harness commands, all three theme lists
include the destination (all three copies in the fixture too). The facade
ratchet shrinks 17,932 → 17,766 with original dated notes retained. The existing
feature registration, bridge/import restrictions and 500-line cap apply.

| Creation verification | Evidence/result |
|---|---|
| Current ownership/history | `step1/current.txt`: zero differences; earlier P1/P2 destinations protected |
| Source guards | Eight remaining legacy readers have no moved P3 anchors (`source-retarget-inventory.json`); chaining reader resolves original settings method to current controller (`reader-moved.txt`); no assertions weakened |
| Optional commas/format | Exactly equals reviewed formatted source; zero inserted/deleted optional commas, idempotent (`tooling/optional-commas.json`); creation format passes |
| Analyzer | Root 1,771 → 1,777; outside-video-player identities/multiplicities exact; scoped 81 diagnostics, zero additions over frozen inventory; all P1/P2 maxima preserved (`step1/root-analyzer-delta.json`, `analyzer.txt`) |
| Declared diagnostic delta | Retained original facade import becomes unused (Step T probe identity); two destination import-order infos; three formatting-exposed brace infos. Original import list preserved, no cleanup/suppression edits. Global warning entry records only that frozen import identity. |
| Sizes/boundaries | 2,995 tracked files / 140 ratchets; new controller capped by architecture; 1,664 migrated files; architecture negatives pass; controller 260, facade 17,766 |
| Affected behavior/source guards | All 150 pass, including all 58 P3 cases, seam/current reader, EOF and theme guards; `p3/step1-affected.jsonl`, unchanged tree during run |

Initial apply helper stopped before modifying the theme fixture because its
frozen path occurs in three lists. Corrected helper/resume extends all three
with original indentation, validates already-materialized application bytes,
and preserves the attempt NOTE. The shrink helper discards baseline comments;
dated history notes were restored before the affected suite. No result from a
failed check is credited. Clean-tree full suite, historical/self checks and
both release builds follow at the gate.


## Phase 3 clean production gate (2026-10-12)

Tested clean creation `575ead0ca`, following addendum `682d86812`; final gate
commit contains "gate". Original remains `fc24e32ae`; Step-0b reuses the clean
`55ac577e6` suite because its addendum changes only documentation/evidence.
`p3/gate/completion.json` records revisions, SDK/flags, hashes and all results.

| Gate | Result / evidence |
|---|---|
| Full suite | 12,931 successes / 13 failures / 28 errors / 20 skips; exact identity/outcome equality to Step-0b baseline; zero missing/added/changed identities, new failures or skips (`p3-gate-suite.jsonl`, `gate/suite-delta.json`, official `suite-comparison.txt`) |
| Clean inputs | Flutter 3.44.8 / Dart 3.12.2, no-pub and hook define; unchanged clean tree during complete suite |
| Analyzer | Root 1,777; expected +6 frozen probe delta, every outside-video-player identity/multiplicity unchanged; scoped root and CI 81, no additions beyond P3 maxima; earlier P1/P2 mappings preserved; global warning list exact (`gate/root-analyzer-delta.json`, comparator/allowlist logs) |
| Format / size / architecture | Full CI format list passes; 2,996 tracked files / 140 ratchets; 1,664 migrated files; architecture negatives pass; facade ratchet 17,766; controller 260 |
| All Dart/Kotlin checks | 31 accepted commands: 26 existing Dart manifest self-tests, P3 universal self-test including real P1/P2/P3 configurations, P3 current, historical P1 `--at 31a347ad2`, P2 `--at fc24e32ae`, Kotlin historical/compiled self-test; all zero exits (`gate/compat-checks.json`) |
| Release builds | `nice -n 19 flutter build apk --release --no-pub` and `flutter build macos --release --no-pub` pass on clean creation; artifact sizes/hashes in `gate/build-results.json`; no install/run |
| Parser routing / constraints | Every manifest invocation has an explicit isolated package under `.dart_tool/vplayer_parser/`; copied kernels deleted, including nested self-tests; both evidence overrides active (`gate/parser-routing-audit.json`); pubspec unchanged, exact two-file application scope, required trailers, branch retained, original mutation source restored |

No application bug fixes, new seams or assertion weakening. The independent
sample remains 20/21 raw (f2 equivalent); full assertion replays correct the six
false compile labels. Systematic 148-point coverage/mutation tables remain
119 killed / 26 equivalent / three classified. Existing profile/cache races
remain documented in Follow-ups. Device checks stay pending: on phone, Android
TV Flutter player, tvOS and desktop, verify Skip intro/credits appears within
the segment, seeks to its end, TV Select works, and episode switching does not
flash the old button. Web unavailable-provider and Android replacement
`playerCreated == false` branches remain classified pending. Stop after gate.

## Phase 3 independent review closure — `vp-rev3` (2026-10-12)

Independent review found no P1s or P2s and one P3: C32's incoming profile
disables skips, so its provider selection cannot affect the assertions.
Keep C32 unchanged and add C59 in the already-registered
`video_player_skip_races_test.dart`. It mounts an enabled outgoing SkipDB
route, disposes it, performs the existing profile handoff, persists enabled
incoming IntroDB settings and mounts the incoming route through the original
caller. Assert one IntroDB request with the exact IMDb/season/episode query
and no additional SkipDB request after handoff and a position tick.

| Coverage addition | Declaration / existing sweep point | Observable contract |
|---|---|---|
| C59: skip incoming enabled profile selects IntroDB without another SkipDB request | `_loadSkipSegmentSettings`, `settings-create-id`; `_syncSkipSegmentsForCurrentContent` | Incoming enabled profile determines provider transport independently of the outgoing SkipDB selection; C32 still covers disabled incoming settings |

| Additional mutation witness | Original mutation | Result / assertion |
|---|---|---|
| `vp-rev3-P3`, C59 (`settings-create-id`) | At `55ac577e6`, `SkipSegmentProviders.create(providerId)` → `SkipSegmentProviders.create(SkipSegmentProviders.skipDb)` (one occurrence) | Killed by C59: expected one IntroDB request, actual zero; completed assertion failure, no compile/load errors |

Evidence: `<git-common-dir>/refactor-evidence/vplayer/p3/review-closure/`.
`results.json` pins the detached worktree at exact `55ac577e6`, test/source
hashes, commands, clean original control (one pass), mutation assertion and
source restoration. The same test input passes on moved application
`d6e91c62a`; `moved-skip-tests.jsonl` records all 59 focused skip tests passing.
`p3-checker.txt` records exhaustive P3 ownership with zero differences;
`completion.json` includes the isolated parser package and deleted copied
kernels. Changed-file format and analyzer pass. The witness strengthens an
existing sweep point; the accepted 148-point sweep and independent sample
totals are unchanged. No production/dependency changes or new CI file needed.


## Phase 4 Step T — display modes tooling (2026-10-12)

Original application is the named merge `890df14d8`; approved design is
`b6f1c2c50`. Evidence lives only in `<git-common-dir>/refactor-evidence/vplayer/p4/`.
The draft remains unapplied. Re-measuring by declaration gives 16 moved
spans and 33 retained references on 32 lines (10 retained members), plus the
patched State constructor. The all-retained snapshot classifies all 868
original spans and reports zero differences.

| Proof | Result / evidence |
|---|---|
| Complete materialization | `draft_vplayer_display_moves.py --base 890df14d8 --parser-package … --probe …/p4/tooling/probe`; exhaustive ownership, facade/destination directives, member order and earlier-destination history compare with zero differences |
| Widget selectors | Register both complete `widget.hideBackButton/hideOptions` → `_host.hideBackButton/hideOptions` selectors in the P4 configuration; existing comparison/registration core supports this opt-in shape without a shared-guard change |
| Binding-only negatives | Missing registration, a lexical `VideoPlayerScreen widget` parameter and a lexical `VpDisplayModeHost _host` parameter are rejected by the binding guard alone; token mismatches cannot supply this proof |
| Frozen scaffolding negatives | Cached and lazy-cached widget values, wrong live forwarder, missing eager display assignment, removed earlier skip assignment, changed State HUD allocation, effectful resume action replacing a direct write, and a destination widget reference are rejected |
| Construction / initializers | `construction-proof.json`: enum constant `AspectMode.contain`, literal `1.0`, implicit `null`, literal `false`; inert constructors only store references and read no Host during construction. Existing eager sleep/skip assignments retained; display appended before `initState`. Both HUD notifier allocations remain at their State positions |
| Host | All 14 specified members have original readers; `controlsVisible` is `ValueNotifier<bool>`, `dockBand(double legacy)` returns `double`, and `saveResume()` remains `Future<void>` called unawaited where originally unawaited. Frozen adapter getters read live `_s.widget` values |
| Formatting | Evidence-only facade/controller formatted (controller 243 lines); zero inserted/deleted optional commas, idempotent, zero comparison differences; no diagnostics introduced or removed by formatting (`optional-commas.json`, `format-diagnostics.json`) |
| Analyzer receiver/rename probe | Original scoped root 81 / strict features 149; materialized root 82. Frozen P4 inventory retains P1/P2/P3 mappings and maxima. `use_build_context_synchronously` identities unchanged: `_switchToSourcePlaylist` ×1, `_toggleRecording` ×4, `build` ×1; no moved declaration gains that identity (`async-context-identities.json`) |
| Compatibility | All 26 existing Dart manifest self-tests, universal video-player self-test including real P1/P2/P3/P4 configurations, Kotlin checker self-test, P1 `--at 31a347ad2`, P2 `--at fc24e32ae`, P3 `--at 890df14d8`; accepted commands/results in `tooling/checks.json` |
| Parser discipline | Each manifest command explicitly selects its own package under `.dart_tool/vplayer_parser/`; copied kernels deleted, including nested manifest/guard fixtures. Evidence overrides route Dart and Kotlin artifacts only to P4 |

CI stays on applied P3 until the Step-1 production commit that creates
`vp_display_mode_controller.dart`. That commit switches current/self and both
analyzer arguments to P4, preserves all three historical checks, registers
the five display characterization files, and extends all three theme path
lists. No CI activation or production move occurs at Step T. The initial
failed interpolation/scaffold probes remain archived as attempts; only zero
exit completed proofs are credited.

## Phase 4 Step 0 — original display characterization (2026-10-12)

Original application: `890df14d8`, detached under `p4/step0/original`.
All tests use original public widget/gesture/menu callers and the existing
player/platform/preference doubles. No new seam or private State invocation.
The complete mutation patches, original AST declaration offsets, statements,
branch/literal points and test hashes are in `step0/points.json`,
`mutation-results.json` and per-point JSONL/stderr/patch files.

38 cases pass on the original; every case has a completed assertion
kill. The systematic sweep covers every moved declaration and each of the
33 retained references: **170 points**, 3 equivalent, 157 killed, 9 dormant, 1 device pending.
Compilation/load failures and uncaught-error-only runs are not credited.

| Moved declaration (original) | Covered behavior / point groups |
|---|---|
| `_aspectMode` | field-aspect |
| `_playbackSpeed` | field-speed |
| `_speedBeforeHold` | field-hold |
| `_landscapeLocked` | field-landscape |
| `_applyAspectVideoZoom` | zoom-native, zoom-mode, zoom-log, zoom-base, zoom-property, zoom-precision, zoom-await, zoom-diagnostic |
| `_cycleAspectMode` | cycle-mode-0, cycle-label-0, cycle-icon-0, cycle-mode-1, cycle-label-1, cycle-icon-1, cycle-mode-2, cycle-label-2, cycle-icon-2, cycle-mode-3, cycle-label-3, cycle-icon-3, cycle-mode-4, cycle-label-4, cycle-icon-4, cycle-mode-5, cycle-label-5, cycle-icon-5, cycle-mode-6, cycle-label-6, cycle-icon-6, cycle-mode-7, cycle-label-7, cycle-icon-7, cycle-mode-8, cycle-label-8, cycle-icon-8, cycle-mode-9, cycle-label-9, cycle-icon-9, cycle-mode-10, cycle-label-10, cycle-icon-10, cycle-dispatch-0, cycle-dispatch-1, cycle-dispatch-2, cycle-dispatch-3, cycle-dispatch-4, cycle-dispatch-5, cycle-dispatch-6, cycle-dispatch-7, cycle-dispatch-8, cycle-dispatch-9, cycle-dispatch-10, cycle-selector, cycle-state, cycle-rebuild, cycle-zoom, cycle-hud-label, cycle-hud-icon, cycle-hud-delay, cycle-hud-early, cycle-hud-mounted, cycle-hud-clear, cycle-autohide, cycle-save |
| `_changeSpeed` | dormant-speed-rates, dormant-speed-index, dormant-speed-wrap, dormant-speed-rate, dormant-speed-state, dormant-speed-hide, dormant-speed-save |
| `_onSpeedButton` | button-speed-gate, button-speed-section, button-speed-return, button-speed-fallback |
| `_onAspectButton` | button-aspect-gate, button-aspect-section, button-aspect-return, button-aspect-fallback |
| `_setPlaybackSpeed` | speed-rate, speed-value, speed-rebuild, speed-save |
| `_setAspectModeDirect` | aspect-same, aspect-value, aspect-rebuild, aspect-zoom, aspect-save |
| `_onLongPressStart` | hold-locked, hold-back, hold-options, hold-paused, hold-edge-width, hold-edge-left, hold-edge-right, hold-visible, hold-top-size, hold-bottom-size, hold-top-boundary, hold-bottom-boundary, hold-prior, hold-rate, hold-value, hold-rebuild, hold-hud, hold-haptic, hold-horizontal-or, hold-vertical-or, hold-box-null |
| `_onLongPressEnd` | end-prior, end-null, end-clear, end-mounted, end-rate, end-value, end-rebuild, end-hud |
| `_toggleOrientation` | orientation-branch, orientation-portrait, orientation-left, orientation-right, orientation-await-portrait, orientation-await-landscape, orientation-portrait-lock, orientation-landscape-lock, orientation-immersive, orientation-mounted, orientation-rebuild, orientation-hide |
| `_currentFit` | fit-result |
| `_getCustomAspectRatio` | ratio-result |

| Retained enclosing member | Individually classified references |
|---|---|
| `_maybeRestoreResume` | `r07` (line 12090), `r08` (line 12092), `r09` (line 12093) |
| `_saveResumeLocked` | `r10` (line 12511), `r11` (line 12514), `r12` (line 12514) |
| `initState` | `r01` (line 1657), `r02` (line 1659) |
| `_createPlayerInstance` | `r03` (line 2656) |
| `_loadPlayerDefaults` | `r04` (line 6208), `r05` (line 6264) |
| `_restoreIosPipPlayer` | `r06` (line 11504) |
| `_buildTvControls` | `r13` (line 12914), `r14` (line 12915), `r15` (line 12918), `r16` (line 12919) |
| `_buildCustomAspectRatioVideo` | `r17` (line 13722), `r18` (line 13723) |
| `build` | `r19` (line 14486), `r20` (line 14751), `r21` (line 14760), `r22` (line 15013), `r23` (line 15014), `r24` (line 15145), `r25` (line 15146), `r26` (line 15149), `r27` (line 15150), `r28` (line 15151), `r29` (line 15152) |
| `_buildPlayerMenuPanel` | `r30` (line 16737), `r31` (line 16738), `r32` (line 16739), `r33` (line 16740) |

| Case | Original caller / asserted behavior | Assertion-failing original witness |
|---|---|---|
| C01 | display aspect key cycles to Cover with rendered ratio HUD zoom and save | `zoom-native` |
| C02 | display aspect key cycles to Fit Width with rendered ratio HUD zoom and save | `zoom-native` |
| C03 | display aspect key cycles to Fit Height with rendered ratio HUD zoom and save | `zoom-native` |
| C04 | display aspect key cycles to 16:9 with rendered ratio HUD zoom and save | `zoom-native` |
| C05 | display aspect key cycles to 4:3 with rendered ratio HUD zoom and save | `zoom-native` |
| C06 | display aspect key cycles to 21:9 with rendered ratio HUD zoom and save | `zoom-native` |
| C07 | display aspect key cycles to 1:1 with rendered ratio HUD zoom and save | `zoom-native` |
| C08 | display aspect key cycles to 3:2 with rendered ratio HUD zoom and save | `zoom-native` |
| C09 | display aspect key cycles to 5:4 with rendered ratio HUD zoom and save | `zoom-native` |
| C10 | display aspect key cycles to Cinema Zoom with rendered ratio HUD zoom and save | `zoom-native` |
| C11 | display aspect key cycles to Contain with rendered ratio HUD zoom and save | `zoom-native` |
| C12 | display aspect pending HUD clear does nothing after disposal | `cycle-hud-mounted` |
| C13 | display aspect menu passes selection and identical aspect is a no-op | `button-aspect-gate` |
| C14 | display non-native aspect path skips native zoom | `r24-build-_onAspectButton` |
| C15 | display native zoom rejection logs once and still applies aspect | `zoom-await` |
| C16 | display defaults seed cinema framing and record the loaded aspect diagnostic | `field-speed` |
| C17 | display TV dock dispatches speed and aspect menus with live selected values and key A | `r13-_buildTvControls-_onSpeedButton` |
| C18 | display styled dock forwards current speed aspect and orientation actions | `aspect-value` |
| C19 | display aspect cycle rearms controls auto-hide from the action time | `cycle-autohide` |
| C20 | display hold lock back=true options=true reads current widget flags | `hold-back` |
| C21 | display hold lock back=true options=false reads current widget flags | `hold-locked` |
| C22 | display hold lock back=false options=true reads current widget flags | `hold-locked` |
| C23 | display hold lock back=false options=false reads current widget flags | `hold-back` |
| C24 | display paused hold and release without a hold have no effects | `field-hold` |
| C25 | display hold edge and visible-bar strict boundaries preserve button regions | `hold-edge-width` |
| C26 | display hidden controls allow top and bottom holds and restore prior speed with one haptic | `hold-visible` |
| C27 | display real pointer hold spans rebuild and releases the same recognizer once | `hold-prior` |
| C28 | display late release after dispose clears hold without changing disposed player rate | `end-mounted` |
| C29 | display desktop landscape seed ignores phone portrait preference and toggles both directions | `orientation-branch` |
| C30 | display overlapping orientation toggles read the same initial lock and rearm one hide timer | `orientation-branch` |
| C31 | display orientation completed after dispose still sends immersive mode and creates a drained timer | `orientation-await-portrait` |
| C32 | display rejected orientation propagates without lock change immersive call or hide timer | `orientation-branch` |
| C33 | display portrait-to-landscape orientation waits for the held channel before lock and timer changes | `orientation-await-landscape` |
| C34 | display speed menu preserves ordered rates wraps selections and persists each selected value | `field-speed` |
| C35 | display queued resume writes sample latest speed and aspect inside the save lock | `r10-_saveResumeLocked-_aspectMode` |
| C36 | display temporary 2x never persists and queued hold saves sample after release and speed change | `aspect-value` |
| C37 | display playlist resume speed 1.0 restores aspect zoom and preserves the 1x skip | `r08-_maybeRestoreResume-_aspectMode` |
| C38 | display playlist resume speed 2.0 restores aspect zoom and preserves the 1x skip | `r07-_maybeRestoreResume-_playbackSpeed` |

| Mutation point | Original statement/branch/literal → mutation | Result / case |
|---|---|---|
| `field-aspect` (_aspectMode:1433) | `AspectMode.contain` → `AspectMode.cover` | equivalent: Awaited defaults overwrite the inert initial value before player creation/rendering. |
| `field-speed` (_playbackSpeed:1434) | `1.0` → `1.25` | killed: C16, C34 |
| `field-hold` (_speedBeforeHold:1444) | `_speedBeforeHold;` → `_speedBeforeHold = 1.75;` | killed: C24, C34 |
| `field-landscape` (_landscapeLocked:1448) | `false` → `true` | equivalent: initState assigns !startsInPortrait before it reads this value or builds controls. |
| `zoom-native` (_applyAspectVideoZoom:2810) | `if (platform is! mk.NativePlayer) return;` → `if (platform is! mk.NativePlayer \|\| mounted) return;` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `zoom-mode` (_applyAspectVideoZoom:2811) | `getScaleForMode(_aspectMode)` → `getScaleForMode(AspectMode.contain)` | killed: C10 |
| `zoom-log` (_applyAspectVideoZoom:2812) | `math.log(scale) / math.ln2` → `scale` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `zoom-base` (_applyAspectVideoZoom:2812) | `math.ln2` → `math.ln10` | killed: C10 |
| `zoom-property` (_applyAspectVideoZoom:2814) | `'video-zoom'` → `'video-scale'` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `zoom-precision` (_applyAspectVideoZoom:2814) | `toStringAsFixed(6)` → `toStringAsFixed(5)` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `zoom-await` (_applyAspectVideoZoom:2814) | `await platform.setProperty` → `platform.setProperty` | killed: C15 |
| `zoom-diagnostic` (_applyAspectVideoZoom:2816) | `aspect zoom apply failed: $e` → `aspect zoom apply failed` | killed: C15 |
| `cycle-mode-0` (_cycleAspectMode:13510) | `newMode = AspectMode.cover;` → `newMode = AspectMode.contain;` | killed: C01 |
| `cycle-label-0` (_cycleAspectMode:13511) | `modeName = 'Cover';` → `modeName = 'changed';` | killed: C01 |
| `cycle-icon-0` (_cycleAspectMode:13510) | `newMode = AspectMode.cover; modeName = 'Cover'; modeIcon = Icons.crop_free_rounded;` → `newMode = AspectMode.cover; modeName = 'Cover'; modeIcon = Icons.close_rounded;` | killed: C01 |
| `cycle-mode-1` (_cycleAspectMode:13515) | `newMode = AspectMode.fitWidth;` → `newMode = AspectMode.cover;` | killed: C02 |
| `cycle-label-1` (_cycleAspectMode:13516) | `modeName = 'Fit Width';` → `modeName = 'changed';` | killed: C02 |
| `cycle-icon-1` (_cycleAspectMode:13515) | `newMode = AspectMode.fitWidth; modeName = 'Fit Width'; modeIcon = Icons.fit_screen_rounded;` → `newMode = AspectMode.fitWidth; modeName = 'Fit Width'; modeIcon = Icons.close_rounded;` | killed: C02 |
| `cycle-mode-2` (_cycleAspectMode:13520) | `newMode = AspectMode.fitHeight;` → `newMode = AspectMode.cover;` | killed: C03 |
| `cycle-label-2` (_cycleAspectMode:13521) | `modeName = 'Fit Height';` → `modeName = 'changed';` | killed: C03 |
| `cycle-icon-2` (_cycleAspectMode:13520) | `newMode = AspectMode.fitHeight; modeName = 'Fit Height'; modeIcon = Icons.fit_screen_roun…` → `newMode = AspectMode.fitHeight; modeName = 'Fit Height'; modeIcon = Icons.close_rounded;` | killed: C03 |
| `cycle-mode-3` (_cycleAspectMode:13525) | `newMode = AspectMode.aspect16_9;` → `newMode = AspectMode.cover;` | killed: C04 |
| `cycle-label-3` (_cycleAspectMode:13526) | `modeName = '16:9';` → `modeName = 'changed';` | killed: C04 |
| `cycle-icon-3` (_cycleAspectMode:13525) | `newMode = AspectMode.aspect16_9; modeName = '16:9'; modeIcon = Icons.aspect_ratio_rounded;` → `newMode = AspectMode.aspect16_9; modeName = '16:9'; modeIcon = Icons.close_rounded;` | killed: C04 |
| `cycle-mode-4` (_cycleAspectMode:13530) | `newMode = AspectMode.aspect4_3;` → `newMode = AspectMode.cover;` | killed: C05 |
| `cycle-label-4` (_cycleAspectMode:13531) | `modeName = '4:3';` → `modeName = 'changed';` | killed: C05 |
| `cycle-icon-4` (_cycleAspectMode:13530) | `newMode = AspectMode.aspect4_3; modeName = '4:3'; modeIcon = Icons.aspect_ratio_rounded;` → `newMode = AspectMode.aspect4_3; modeName = '4:3'; modeIcon = Icons.close_rounded;` | killed: C05 |
| `cycle-mode-5` (_cycleAspectMode:13535) | `newMode = AspectMode.aspect21_9;` → `newMode = AspectMode.cover;` | killed: C06 |
| `cycle-label-5` (_cycleAspectMode:13536) | `modeName = '21:9';` → `modeName = 'changed';` | killed: C06 |
| `cycle-icon-5` (_cycleAspectMode:13535) | `newMode = AspectMode.aspect21_9; modeName = '21:9'; modeIcon = Icons.aspect_ratio_rounded;` → `newMode = AspectMode.aspect21_9; modeName = '21:9'; modeIcon = Icons.close_rounded;` | killed: C06 |
| `cycle-mode-6` (_cycleAspectMode:13540) | `newMode = AspectMode.aspect1_1;` → `newMode = AspectMode.cover;` | killed: C07 |
| `cycle-label-6` (_cycleAspectMode:13541) | `modeName = '1:1';` → `modeName = 'changed';` | killed: C07 |
| `cycle-icon-6` (_cycleAspectMode:13540) | `newMode = AspectMode.aspect1_1; modeName = '1:1'; modeIcon = Icons.crop_square_rounded;` → `newMode = AspectMode.aspect1_1; modeName = '1:1'; modeIcon = Icons.close_rounded;` | killed: C07 |
| `cycle-mode-7` (_cycleAspectMode:13545) | `newMode = AspectMode.aspect3_2;` → `newMode = AspectMode.cover;` | killed: C08 |
| `cycle-label-7` (_cycleAspectMode:13546) | `modeName = '3:2';` → `modeName = 'changed';` | killed: C08 |
| `cycle-icon-7` (_cycleAspectMode:13545) | `newMode = AspectMode.aspect3_2; modeName = '3:2'; modeIcon = Icons.aspect_ratio_rounded;` → `newMode = AspectMode.aspect3_2; modeName = '3:2'; modeIcon = Icons.close_rounded;` | killed: C08 |
| `cycle-mode-8` (_cycleAspectMode:13550) | `newMode = AspectMode.aspect5_4;` → `newMode = AspectMode.cover;` | killed: C09 |
| `cycle-label-8` (_cycleAspectMode:13551) | `modeName = '5:4';` → `modeName = 'changed';` | killed: C09 |
| `cycle-icon-8` (_cycleAspectMode:13550) | `newMode = AspectMode.aspect5_4; modeName = '5:4'; modeIcon = Icons.aspect_ratio_rounded;` → `newMode = AspectMode.aspect5_4; modeName = '5:4'; modeIcon = Icons.close_rounded;` | killed: C09 |
| `cycle-mode-9` (_cycleAspectMode:13555) | `newMode = AspectMode.cinemaZoom;` → `newMode = AspectMode.cover;` | killed: C10 |
| `cycle-label-9` (_cycleAspectMode:13556) | `modeName = 'Cinema Zoom';` → `modeName = 'changed';` | killed: C10 |
| `cycle-icon-9` (_cycleAspectMode:13555) | `newMode = AspectMode.cinemaZoom; modeName = 'Cinema Zoom'; modeIcon = Icons.zoom_in_map_r…` → `newMode = AspectMode.cinemaZoom; modeName = 'Cinema Zoom'; modeIcon = Icons.close_rounded;` | killed: C10 |
| `cycle-mode-10` (_cycleAspectMode:13560) | `newMode = AspectMode.contain;` → `newMode = AspectMode.cover;` | killed: C11 |
| `cycle-label-10` (_cycleAspectMode:13561) | `modeName = 'Contain';` → `modeName = 'changed';` | killed: C11 |
| `cycle-icon-10` (_cycleAspectMode:13560) | `newMode = AspectMode.contain; modeName = 'Contain'; modeIcon = Icons.crop_free_rounded;` → `newMode = AspectMode.contain; modeName = 'Contain'; modeIcon = Icons.close_rounded;` | killed: C11 |
| `cycle-dispatch-0` (_cycleAspectMode:13509) | `case AspectMode.contain: newMode = AspectMode.cover; modeName = 'Cover'; modeIcon = Icons…` → `case AspectMode.cover: newMode = AspectMode.cover; modeName = 'Cover'; modeIcon = Icons.c…` | killed: C01 |
| `cycle-dispatch-1` (_cycleAspectMode:13514) | `case AspectMode.cover: newMode = AspectMode.fitWidth; modeName = 'Fit Width'; modeIcon = …` → `case AspectMode.fitWidth: newMode = AspectMode.fitWidth; modeName = 'Fit Width'; modeIcon…` | killed: C02 |
| `cycle-dispatch-2` (_cycleAspectMode:13519) | `case AspectMode.fitWidth: newMode = AspectMode.fitHeight; modeName = 'Fit Height'; modeIc…` → `case AspectMode.fitHeight: newMode = AspectMode.fitHeight; modeName = 'Fit Height'; modeI…` | killed: C03 |
| `cycle-dispatch-3` (_cycleAspectMode:13524) | `case AspectMode.fitHeight: newMode = AspectMode.aspect16_9; modeName = '16:9'; modeIcon =…` → `case AspectMode.aspect16_9: newMode = AspectMode.aspect16_9; modeName = '16:9'; modeIcon …` | killed: C04 |
| `cycle-dispatch-4` (_cycleAspectMode:13529) | `case AspectMode.aspect16_9: newMode = AspectMode.aspect4_3; modeName = '4:3'; modeIcon = …` → `case AspectMode.aspect4_3: newMode = AspectMode.aspect4_3; modeName = '4:3'; modeIcon = I…` | killed: C05 |
| `cycle-dispatch-5` (_cycleAspectMode:13534) | `case AspectMode.aspect4_3: newMode = AspectMode.aspect21_9; modeName = '21:9'; modeIcon =…` → `case AspectMode.aspect21_9: newMode = AspectMode.aspect21_9; modeName = '21:9'; modeIcon …` | killed: C06 |
| `cycle-dispatch-6` (_cycleAspectMode:13539) | `case AspectMode.aspect21_9: newMode = AspectMode.aspect1_1; modeName = '1:1'; modeIcon = …` → `case AspectMode.aspect1_1: newMode = AspectMode.aspect1_1; modeName = '1:1'; modeIcon = I…` | killed: C07 |
| `cycle-dispatch-7` (_cycleAspectMode:13544) | `case AspectMode.aspect1_1: newMode = AspectMode.aspect3_2; modeName = '3:2'; modeIcon = I…` → `case AspectMode.aspect3_2: newMode = AspectMode.aspect3_2; modeName = '3:2'; modeIcon = I…` | killed: C08 |
| `cycle-dispatch-8` (_cycleAspectMode:13549) | `case AspectMode.aspect3_2: newMode = AspectMode.aspect5_4; modeName = '5:4'; modeIcon = I…` → `case AspectMode.aspect5_4: newMode = AspectMode.aspect5_4; modeName = '5:4'; modeIcon = I…` | killed: C09 |
| `cycle-dispatch-9` (_cycleAspectMode:13554) | `case AspectMode.aspect5_4: newMode = AspectMode.cinemaZoom; modeName = 'Cinema Zoom'; mod…` → `case AspectMode.cinemaZoom: newMode = AspectMode.cinemaZoom; modeName = 'Cinema Zoom'; mo…` | killed: C10 |
| `cycle-dispatch-10` (_cycleAspectMode:13509) | `case AspectMode.contain: newMode = AspectMode.cover; modeName = 'Cover'; modeIcon = Icons…` → `case AspectMode.cinemaZoom: newMode = AspectMode.cover; modeName = 'Cover'; modeIcon = Ic…` | killed: C11 |
| `cycle-selector` (_cycleAspectMode:13508) | `switch (_aspectMode)` → `switch (AspectMode.contain)` | killed: C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `cycle-state` (_cycleAspectMode:13567) | `_aspectMode = newMode;` → `_aspectMode = AspectMode.contain;` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10 |
| `cycle-rebuild` (_cycleAspectMode:13566) | `setState(() { _aspectMode = newMode; });` → `_aspectMode = newMode;` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `cycle-zoom` (_cycleAspectMode:13569) | `unawaited(_applyAspectVideoZoom());` → `// zoom removed` | killed: C10, C11 |
| `cycle-hud-label` (_cycleAspectMode:13573) | `aspectRatio: modeName,` → `aspectRatio: 'changed',` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `cycle-hud-icon` (_cycleAspectMode:13574) | `icon: modeIcon,` → `icon: Icons.close_rounded,` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `cycle-hud-delay` (_cycleAspectMode:13578) | `milliseconds: 1500` → `milliseconds: 1501` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `cycle-hud-early` (_cycleAspectMode:13578) | `milliseconds: 1500` → `milliseconds: 1499` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `cycle-hud-mounted` (_cycleAspectMode:13579) | `if (mounted)` → `if (true)` | killed: C12 |
| `cycle-hud-clear` (_cycleAspectMode:13580) | `_aspectRatioHud.value = null;` → `// HUD clear removed` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `cycle-autohide` (_cycleAspectMode:13584) | `_scheduleAutoHide();` → `// auto hide removed` | killed: C19 |
| `cycle-save` (_cycleAspectMode:13585) | `_saveResume();` → `// save removed` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11 |
| `dormant-speed-rates` (_changeSpeed:13589) | `[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]` → `[1.0]` | dormant: Only caller is disabled by const kUnifiedPlayerMenuEnabled=true. |
| `dormant-speed-index` (_changeSpeed:13590) | `speeds.indexOf(_playbackSpeed)` → `0` | dormant: Only caller is disabled by const kUnifiedPlayerMenuEnabled=true. |
| `dormant-speed-wrap` (_changeSpeed:13591) | `(idx + 1) % speeds.length` → `idx` | dormant: Only caller is disabled by const kUnifiedPlayerMenuEnabled=true. |
| `dormant-speed-rate` (_changeSpeed:13592) | `_player.setRate(next);` → `// rate removed` | dormant: Only caller is disabled by const kUnifiedPlayerMenuEnabled=true. |
| `dormant-speed-state` (_changeSpeed:13593) | `setState(() => _playbackSpeed = next);` → `// state removed` | dormant: Only caller is disabled by const kUnifiedPlayerMenuEnabled=true. |
| `dormant-speed-hide` (_changeSpeed:13594) | `_scheduleAutoHide();` → `// hide removed` | dormant: Only caller is disabled by const kUnifiedPlayerMenuEnabled=true. |
| `dormant-speed-save` (_changeSpeed:13595) | `_saveResume();` → `// save removed` | dormant: Only caller is disabled by const kUnifiedPlayerMenuEnabled=true. |
| `button-speed-gate` (_onSpeedButton:13601) | `if (kUnifiedPlayerMenuEnabled)` → `if (!kUnifiedPlayerMenuEnabled)` | killed: C34 |
| `button-speed-section` (_onSpeedButton:13602) | `PlayerMenuSection.speed` → `PlayerMenuSection.audio` | killed: C34 |
| `button-speed-return` (_onSpeedButton:13603) | `return;` → `// return removed` | killed: C34 |
| `button-speed-fallback` (_onSpeedButton:13605) | `_changeSpeed();` → `// fallback removed` | dormant: Const enabled menu returns before this statement. |
| `button-aspect-gate` (_onAspectButton:13609) | `if (kUnifiedPlayerMenuEnabled)` → `if (!kUnifiedPlayerMenuEnabled)` | killed: C13 |
| `button-aspect-section` (_onAspectButton:13610) | `PlayerMenuSection.aspect` → `PlayerMenuSection.audio` | killed: C13 |
| `button-aspect-return` (_onAspectButton:13611) | `return;` → `// return removed` | killed: C13 |
| `button-aspect-fallback` (_onAspectButton:13613) | `_cycleAspectMode();` → `// fallback removed` | dormant: Const enabled menu returns before this statement. |
| `speed-rate` (_setPlaybackSpeed:13617) | `_player.setRate(v);` → `_player.setRate(1.0);` | killed: C34 |
| `speed-value` (_setPlaybackSpeed:13618) | `_playbackSpeed = v` → `_playbackSpeed = 1.0` | killed: C34 |
| `speed-rebuild` (_setPlaybackSpeed:13618) | `setState(() => _playbackSpeed = v);` → `_playbackSpeed = v;` | killed: C34 |
| `speed-save` (_setPlaybackSpeed:13619) | `_saveResume();` → `// save removed` | killed: C34 |
| `aspect-same` (_setAspectModeDirect:13623) | `if (m == _aspectMode) return;` → `// same-aspect guard removed` | killed: C13 |
| `aspect-value` (_setAspectModeDirect:13624) | `_aspectMode = m` → `_aspectMode = AspectMode.contain` | killed: C18, C36 |
| `aspect-rebuild` (_setAspectModeDirect:13624) | `setState(() => _aspectMode = m);` → `_aspectMode = m;` | killed: C18, C36 |
| `aspect-zoom` (_setAspectModeDirect:13625) | `unawaited(_applyAspectVideoZoom());` → `// zoom removed` | killed: C15 |
| `aspect-save` (_setAspectModeDirect:13626) | `_saveResume();` → `// save removed` | killed: C13, C36 |
| `hold-locked` (_onLongPressStart:13631) | `widget.hideBackButton && widget.hideOptions` → `widget.hideBackButton \|\| widget.hideOptions` | killed: C21, C22 |
| `hold-back` (_onLongPressStart:13631) | `widget.hideBackButton && widget.hideOptions` → `false && widget.hideOptions` | killed: C20, C21, C22, C23 |
| `hold-options` (_onLongPressStart:13631) | `widget.hideBackButton && widget.hideOptions` → `widget.hideBackButton && false` | killed: C20, C21, C22, C23 |
| `hold-paused` (_onLongPressStart:13633) | `if (!_isPlaying) return;` → `// pause guard removed` | killed: C24 |
| `hold-edge-width` (_onLongPressStart:13639) | `const edgeGuard = 24.0;` → `const edgeGuard = 0.0;` | killed: C25 |
| `hold-edge-left` (_onLongPressStart:13640) | `localPos.dx < edgeGuard` → `localPos.dx <= edgeGuard` | killed: C25 |
| `hold-edge-right` (_onLongPressStart:13640) | `localPos.dx > size.width - edgeGuard` → `localPos.dx >= size.width - edgeGuard` | killed: C25 |
| `hold-visible` (_onLongPressStart:13644) | `if (_controlsVisible.value)` → `if (true)` | killed: C26 |
| `hold-top-size` (_onLongPressStart:13645) | `const topBar = 72.0;` → `const topBar = 0.0;` | killed: C25 |
| `hold-bottom-size` (_onLongPressStart:13646) | `_dockBand(72.0)` → `_dockBand(0.0)` | killed: C25 |
| `hold-top-boundary` (_onLongPressStart:13647) | `localPos.dy < topBar` → `localPos.dy <= topBar` | killed: C25 |
| `hold-bottom-boundary` (_onLongPressStart:13647) | `localPos.dy > size.height - bottomBar` → `localPos.dy >= size.height - bottomBar` | killed: C25 |
| `hold-prior` (_onLongPressStart:13652) | `_speedBeforeHold = _playbackSpeed;` → `_speedBeforeHold = 1.0;` | killed: C26, C27, C36 |
| `hold-rate` (_onLongPressStart:13653) | `_player.setRate(2.0);` → `_player.setRate(1.0);` | killed: C21, C22, C23, C26, C27 |
| `hold-value` (_onLongPressStart:13654) | `_playbackSpeed = 2.0` → `_playbackSpeed = 1.0` | killed: C21, C22, C23, C26, C36 |
| `hold-rebuild` (_onLongPressStart:13654) | `setState(() => _playbackSpeed = 2.0);` → `_playbackSpeed = 2.0;` | killed: C21, C22, C23, C26, C36 |
| `hold-hud` (_onLongPressStart:13655) | `_speedHoldHud.value = true;` → `_speedHoldHud.value = false;` | killed: C21, C22, C23, C26, C27 |
| `hold-haptic` (_onLongPressStart:13656) | `HapticFeedback.mediumImpact();` → `HapticFeedback.lightImpact();` | killed: C26 |
| `hold-horizontal-or` (_onLongPressStart:13640) | `localPos.dx < edgeGuard \|\| localPos.dx > size.width - edgeGuard` → `localPos.dx < edgeGuard && localPos.dx > size.width - edgeGuard` | killed: C25 |
| `hold-vertical-or` (_onLongPressStart:13647) | `localPos.dy < topBar \|\| localPos.dy > size.height - bottomBar` → `localPos.dy < topBar && localPos.dy > size.height - bottomBar` | killed: C25 |
| `hold-box-null` (_onLongPressStart:13635) | `if (box != null)` → `if (box == null) return; if (true)` | equivalent: Mounted original State renders a non-null RenderBox; no caller invokes start after disposal. Retain safety branch; no test-only private invocation. |
| `end-prior` (_onLongPressEnd:13660) | `final prior = _speedBeforeHold;` → `final prior = 1.0;` | killed: C26, C27, C36 |
| `end-null` (_onLongPressEnd:13661) | `if (prior == null) return;` → `if (prior == null) { _player.setRate(2.0); return; }` | killed: C24 |
| `end-clear` (_onLongPressEnd:13662) | `_speedBeforeHold = null;` → `// prior clear removed` | killed: C36 |
| `end-mounted` (_onLongPressEnd:13663) | `if (!mounted) return;` → `// mounted guard removed` | killed: C28 |
| `end-rate` (_onLongPressEnd:13664) | `_player.setRate(prior);` → `_player.setRate(1.0);` | killed: C26, C27 |
| `end-value` (_onLongPressEnd:13665) | `_playbackSpeed = prior` → `_playbackSpeed = 1.0` | killed: C26, C27, C36 |
| `end-rebuild` (_onLongPressEnd:13665) | `setState(() => _playbackSpeed = prior);` → `_playbackSpeed = prior;` | killed: C26, C27, C36 |
| `end-hud` (_onLongPressEnd:13666) | `_speedHoldHud.value = false;` → `_speedHoldHud.value = true;` | killed: C26, C27, C36 |
| `orientation-branch` (_toggleOrientation:13670) | `if (_landscapeLocked)` → `if (!_landscapeLocked)` | killed: C18, C29, C30, C32 |
| `orientation-portrait` (_toggleOrientation:13672) | `DeviceOrientation.portraitUp` → `DeviceOrientation.portraitDown` | killed: C18, C29, C30, C32 |
| `orientation-left` (_toggleOrientation:13677) | `DeviceOrientation.landscapeLeft,` → `DeviceOrientation.landscapeRight,` | killed: C29 |
| `orientation-right` (_toggleOrientation:13678) | `DeviceOrientation.landscapeRight,` → `DeviceOrientation.landscapeLeft,` | killed: C29 |
| `orientation-await-portrait` (_toggleOrientation:13671) | `await SystemChrome.setPreferredOrientations` → `SystemChrome.setPreferredOrientations` | killed: C30, C31, C32 |
| `orientation-await-landscape` (_toggleOrientation:13676) | `await SystemChrome.setPreferredOrientations` → `SystemChrome.setPreferredOrientations` | killed: C33 |
| `orientation-portrait-lock` (_toggleOrientation:13674) | `_landscapeLocked = false;` → `_landscapeLocked = true;` | killed: C18, C29, C30 |
| `orientation-landscape-lock` (_toggleOrientation:13680) | `_landscapeLocked = true;` → `_landscapeLocked = false;` | killed: C29 |
| `orientation-immersive` (_toggleOrientation:13682) | `SystemUiMode.immersiveSticky` → `SystemUiMode.edgeToEdge` | killed: C29, C31 |
| `orientation-mounted` (_toggleOrientation:13683) | `if (mounted) setState(() {});` → `setState(() {});` | killed: C31 |
| `orientation-rebuild` (_toggleOrientation:13683) | `if (mounted) setState(() {});` → `// state rebuild removed` | killed: C18, C29, C30 |
| `orientation-hide` (_toggleOrientation:13684) | `_scheduleAutoHide();` → `// auto hide removed` | killed: C29, C30, C31 |
| `fit-result` (_currentFit:13687) | `getBoxFitForMode(_aspectMode)` → `getBoxFitForMode(AspectMode.contain)` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09 |
| `resume-one-skip` (_maybeRestoreResume:12088) | `if (speed != 1.0)` → `if (true)` | killed: C37 |
| `resume-queued-speed` (_saveResumeLocked:12514) | `_speedBeforeHold ?? _playbackSpeed` → `1.25` | killed: C35 |
| `ratio-result` (_getCustomAspectRatio:13895) | `getAspectRatioValue(_aspectMode)` → `getAspectRatioValue(AspectMode.contain)` | killed: C04, C05, C06, C07, C08, C09 |
| `r01-initState-_landscapeLocked` (initState:1657) | `_landscapeLocked = !_startsInPortrait;` → `/* retained write removed */` | killed: C18, C29, C30, C32 |
| `r02-initState-_landscapeLocked` (initState:1659) | `_landscapeLocked` → `false` | killed: C29 |
| `r03-_createPlayerInstance-_applyAspectVideoZoom` (_createPlayerInstance:2656) | `_applyAspectVideoZoom()` → `Future<void>.value()` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11, C16 |
| `r04-_loadPlayerDefaults-_aspectMode` (_loadPlayerDefaults:6208) | `_aspectMode = aspects[aspectIndex.clamp(0, aspects.length - 1)];` → `/* retained write removed */` | killed: C02, C03, C04, C05, C06, C07, C08, C09, C10, C11, C16 |
| `r05-_loadPlayerDefaults-_aspectMode` (_loadPlayerDefaults:6264) | `$_aspectMode` → `changed` | killed: C16 |
| `r06-_restoreIosPipPlayer-_landscapeLocked` (_restoreIosPipPlayer:11504) | `_landscapeLocked` → `false` | device_pending: Real Platform.isIOS and PiP lifecycle; no additional seam authorized. |
| `r07-_maybeRestoreResume-_playbackSpeed` (_maybeRestoreResume:12090) | `_playbackSpeed = speed;` → `/* retained write removed */` | killed: C38 |
| `r08-_maybeRestoreResume-_aspectMode` (_maybeRestoreResume:12092) | `_aspectMode = AspectModeUtils.stringToAspectMode(aspect);` → `/* retained write removed */` | killed: C37, C38 |
| `r09-_maybeRestoreResume-_applyAspectVideoZoom` (_maybeRestoreResume:12093) | `_applyAspectVideoZoom()` → `Future<void>.value()` | killed: C38 |
| `r10-_saveResumeLocked-_aspectMode` (_saveResumeLocked:12511) | `_aspectMode` → `AspectMode.contain` | killed: C35, C36 |
| `r11-_saveResumeLocked-_speedBeforeHold` (_saveResumeLocked:12514) | `_speedBeforeHold` → `null` | killed: C36 |
| `r12-_saveResumeLocked-_playbackSpeed` (_saveResumeLocked:12514) | `_playbackSpeed` → `1.0` | killed: C34 |
| `r13-_buildTvControls-_onSpeedButton` (_buildTvControls:12914) | `_onSpeedButton` → `() {}` | killed: C17 |
| `r14-_buildTvControls-_onAspectButton` (_buildTvControls:12915) | `_onAspectButton` → `() {}` | killed: C17 |
| `r15-_buildTvControls-_playbackSpeed` (_buildTvControls:12918) | `_playbackSpeed` → `1.0` | killed: C17 |
| `r16-_buildTvControls-_aspectMode` (_buildTvControls:12919) | `_aspectMode` → `AspectMode.contain` | killed: C17 |
| `r17-_buildCustomAspectRatioVideo-_getCustomAspectRatio` (_buildCustomAspectRatioVideo:13722) | `_getCustomAspectRatio()` → `null` | killed: C04, C05, C06, C07, C08, C09 |
| `r18-_buildCustomAspectRatioVideo-_currentFit` (_buildCustomAspectRatioVideo:13723) | `_currentFit()` → `BoxFit.contain` | killed: C04, C05, C06, C07, C08, C09 |
| `r19-build-_cycleAspectMode` (build:14486) | `_cycleAspectMode()` → `(() {})()` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11, C12, C17 |
| `r20-build-_getCustomAspectRatio` (build:14751) | `_getCustomAspectRatio()` → `null` | killed: C04, C05, C06, C07, C08, C09, C13, C18, C37 |
| `r21-build-_currentFit` (build:14760) | `_currentFit()` → `BoxFit.contain` | killed: C01, C02, C03 |
| `r22-build-_onLongPressStart` (build:15013) | `_onLongPressStart` → `(LongPressStartDetails _) {}` | killed: C21, C22, C23, C25, C26, C27, C36 |
| `r23-build-_onLongPressEnd` (build:15014) | `_onLongPressEnd` → `(LongPressEndDetails _) {}` | killed: C25, C26, C27, C36 |
| `r24-build-_onAspectButton` (build:15145) | `_onAspectButton` → `() {}` | killed: C13, C14, C15, C18, C35, C36 |
| `r25-build-_onSpeedButton` (build:15146) | `_onSpeedButton` → `() {}` | killed: C18, C26, C27, C28, C34, C35, C36, C37, C38 |
| `r26-build-_playbackSpeed` (build:15149) | `_playbackSpeed` → `1.0` | killed: C18, C21, C22, C23, C26, C27, C28, C34, C35, C36, C37, C38 |
| `r27-build-_aspectMode` (build:15150) | `_aspectMode` → `AspectMode.contain` | killed: C01, C02, C03, C04, C05, C06, C07, C08, C09, C10, C11, C13, C14, C15, C16, C18, C35, C36, C37, C38 |
| `r28-build-_landscapeLocked` (build:15151) | `_landscapeLocked` → `false` | killed: C29, C30, C32 |
| `r29-build-_toggleOrientation` (build:15152) | `_toggleOrientation` → `() async {}` | killed: C18, C29, C30, C31, C32 |
| `r30-_buildPlayerMenuPanel-_playbackSpeed` (_buildPlayerMenuPanel:16737) | `_playbackSpeed` → `1.0` | killed: C18 |
| `r31-_buildPlayerMenuPanel-_setPlaybackSpeed` (_buildPlayerMenuPanel:16738) | `_setPlaybackSpeed` → `(double _) {}` | killed: C18, C34 |
| `r32-_buildPlayerMenuPanel-_aspectMode` (_buildPlayerMenuPanel:16739) | `_aspectMode` → `AspectMode.contain` | killed: C18 |
| `r33-_buildPlayerMenuPanel-_setAspectModeDirect` (_buildPlayerMenuPanel:16740) | `_setAspectModeDirect` → `(AspectMode _) {}` | killed: C13, C18 |

**Reachability/equivalence.** The inert aspect initializer is overwritten by
awaited defaults before player creation; the landscape initializer is
overwritten synchronously in `initState` before its first read. Both altered
initial values pass the complete original controls. Gesture start is delivered
on a mounted rendered State with a non-null `RenderBox`; the box-null fallback
is unreachable through the supported callers. Each candidate has a completed
surviving replay and caller-order evidence, while its source remains frozen.
The legacy speed cycle (all seven rates/index/wrap/effects) and the two disabled
menu fallback calls are dormant behind the constant unified-menu flag.
Phone-only portrait seed and PiP landscape restore remain device-pending;
desktop landscape seeding and both orientation directions are covered.

**Preserved details.** HUD clear is 1.5 seconds and does not clear after
disposal: the test observes the notifier exposed by the rendered widget.
That notifier is not disposed in the original; no cleanup fix is included.
Orientation completion after disposal still sends immersive mode and creates
a three-second auto-hide timer, which is explicitly drained. Held toggles in
both directions, overlap and channel rejection pin locks, channel ordering
and timer creation/cancellation. Resume tests select the series guide with
saved progress so the real allow-resume caller runs; saved 1.0 skips both
rate and field assignment. Queued saves sample current fields inside the
existing save lock and held 2× is not persisted.

**Development attempts.** The first controls exposed fixture expectations
for list identity, duplicate rail/value text, auto-selected resume entries
and manual-next resume suppression. Corrected caller fixtures retain the
required assertions. An invalid native-guard mutation is replaced by a
flow-valid gate mutation. The initial post-dispose orientation error alone
is replaced by an explicit captured-error assertion. All attempts are
archived and excluded from accepted results. Two preliminary direct runs
inherited the harness P2 runtime default; their 72 newly created directories
were relocated into P4 by the exact run timestamp bounds
(`runtime-routing-note.json`). Accepted controls/mutations explicitly set
`VPLAYER_EVIDENCE_ROOT` and Kotlin evidence overrides to P4.

CI registration of the five new display files accompanies the future
Step-1 production creation and P4 current/analyzer transition. Independent
Claude sampling and phone/TV/tvOS end-of-series checks remain subsequent
review/device work. No production move, bug fix or dependency change.
