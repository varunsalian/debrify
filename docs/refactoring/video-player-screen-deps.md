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

The 38 accepted cases plus C39/C40 from **vp-rev4** pass on the original;
every case has a completed assertion kill. Corrected coverage spans every
moved declaration and all 33 retained references: **170 points**, 2 equivalent,
158 killed, 9 dormant, 1 device pending. Original logs remain archived;
`vp-rev4/coverage.json` supersedes the false `field-aspect` equivalence.
Compilation/load failures and uncaught-error-only runs are not credited.

| Moved declaration (original) | Covered behavior / point groups |
|---|---|
| `_aspectMode` | field-aspect; C39 defaults-held key A / HUD / zoom error / blocked save |
| `_playbackSpeed` | field-speed; C39/C40 post-defaults 1.0 and ready save; early callers audited below |
| `_speedBeforeHold` | field-hold; C40 real paused hold/release before player creation |
| `_landscapeLocked` | field-landscape; C39/C40 early replay and synchronous initState overwrite proof |
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

| Case | New original-caller behavior | Assertion witness |
|---|---|---|
| C39 | Key A while defaults storage is held: Cover HUD/icon, one early-player error, no zoom transport/write; exact 1.5 s clear; defaults override and ready zoom/save | `field-aspect` |
| C40 | Real paused pointer hold/release while defaults wait; null prior avoids player access; synchronous orientation seed; speed 1.0 after defaults | `field-hold`, `field-speed` |

| Mutation point | Original statement/branch/literal → mutation | Result / case |
|---|---|---|
| `field-aspect` (_aspectMode:1433) | `AspectMode.contain` → `AspectMode.cover` | killed: C39; defaults-held key A renders Cover rather than mutant Fit Width (vp-rev4 correction). |
| `field-speed` (_playbackSpeed:1434) | `1.0` → `1.25` | killed: C16, C34, C40 |
| `field-hold` (_speedBeforeHold:1444) | `_speedBeforeHold;` → `_speedBeforeHold = 1.75;` | killed: C24, C34, C40 |
| `field-landscape` (_landscapeLocked:1448) | `false` → `true` | equivalent: synchronous initState assigns !startsInPortrait before orientation/async initialization/build; both early C39/C40 replay unchanged (vp-rev4). |
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

**Reachability/equivalence (corrected by vp-rev4).** The aspect initializer
is inert but observable: key A cycles it while defaults await storage, and
the HUD renders before readiness. C39 kills its mutation; the previous
equivalence claim was wrong. The landscape initializer is overwritten
synchronously in `initState` before orientation, async initialization and
input dispatch; its mutation passes both early-window cases. Gesture start is
delivered on a mounted rendered State with a non-null `RenderBox`; the box-null fallback
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


## Phase 4 clean Step-0 suite baseline (2026-10-12)

Clean characterization checkpoint `5e08bb3a3`, following tooling `1816a0ee5`;
original is the freshly measured `890df14d8`. Serialized `nice -n 19`
`suite_evidence.py run vplayer/p4/step0-suite --no-pub
--dart-define=DEBRIFY_VP_TEST_HOOKS=true`, same SDK/configuration as the original.

| Baseline check | Result |
|---|---|
| Original full suite | 12,932 successes / 13 failures / 28 errors / 20 skips; exact previous P3 gate outcomes plus its accepted incoming-profile test |
| New full suite | 12,970 successes / 13 failures / 28 errors / 20 skips |
| Identity delta | Exactly 38 added successes; zero missing identities, changed original outcomes, new failures or skips; official suite comparator PASS |
| Focused / mutation coverage | Recorded checkpoint: 38 cases pass with witnesses. vp-rev4 adds C39/C40 and corrects the current 170-point matrix to 158 killed, two equivalent, nine dormant, one PiP device-pending; see review closure below. |
| Other checks | All 31 Dart/Kotlin self/history commands pass; complete virtual P4 split and original 868-span self-compare: zero differences. Analyzer forms/identities, optional-comma/idempotence proof, format, test/support analyzer, size and architecture pass |
| Inputs / evidence | Clean tree throughout the suite, application and pubspec unchanged from original; original mutations restored; isolated parser audit has no violations. `p4/step0/completion.json`, `suite-delta.json`, suite/env/compare logs and detailed mutation artifacts |

No failures were accepted through allowlisting. The recorded preliminary
runtime-root deviation was corrected before accepted evidence; details remain
in Progress and `runtime-routing-note.json`. Production moves and CI activation
remain for Step 1. Phone portrait-start seed/PiP restore and end-of-series
phone/TV/tvOS/desktop framing, speed, gesture and orientation checks are pending.
Stop after Step 0.

## Phase 4 independent sample — original `5e08bb3a3` (2026-10-12)

Claude's separate 173-case original-caller sample (`p4/claude-sample/`)
kills 19/20 raw; g20 is equivalent, so **19/19 valid = 100%**.
All 19 kills have assertion failures and no compile errors. This complements
the systematic 170-point sweep above; no addendum or production fix is needed.
Normalized results and source hashes: `p4/step1/independent-sample.json`.

| Mutation | Original behaviour changed | Outcome / assertion witness |
|---|---|---|
| `g1` | Cover → Fit Height | killed: display aspect key cycles to Fit Width with rendered ratio HUD zoom and save |
| `g2` | Cinema Zoom HUD label | killed: display aspect key cycles to Cinema Zoom with rendered ratio HUD zoom and save |
| `g3` | HUD clear 1500 → 3000 ms | killed: display aspect key cycles to Cover with rendered ratio HUD zoom and save |
| `g4` | Zoom logarithm denominator removed | killed: display defaults seed cinema framing and record the loaded aspect diagnostic |
| `g5` | Zoom decimal precision 6 → 3 | killed: display defaults seed cinema framing and record the loaded aspect diagnostic |
| `g6` | Selected speed resume save removed | killed: display speed menu preserves ordered rates wraps selections and persists each selected value |
| `g7` | Same-aspect early return removed | killed: display aspect menu passes selection and identical aspect is a no-op |
| `g8` | Both locked flags → either locked flag | killed: display hold lock back=true options=false reads current widget flags |
| `g9` | Paused hold guard removed | killed: display paused hold and release without a hold have no effects |
| `g10` | Edge guard 24 → 48 | killed: display hold edge and visible-bar strict boundaries preserve button regions |
| `g11` | Top bar 72 → 36 | killed: display hold edge and visible-bar strict boundaries preserve button regions |
| `g12` | Held speed 2.0 → 1.5 | killed: display hold lock back=true options=false reads current widget flags |
| `g13` | Held HUD true → false | killed: display hold lock back=true options=false reads current widget flags |
| `g14` | Prior-speed clear removed | killed: display temporary 2x never persists and queued hold saves sample after release and speed change |
| `g15` | Landscape Right omitted | killed: display desktop landscape seed ignores phone portrait preference and toggles both directions |
| `g16` | Immersive mode omitted | killed: display desktop landscape seed ignores phone portrait preference and toggles both directions |
| `g17` | Rendered fit always contain | killed: display aspect key cycles to Cover with rendered ratio HUD zoom and save |
| `g18` | Custom ratio always null | killed: display styled dock forwards current speed aspect and orientation actions |
| `g19` | Persist held speed instead of prior speed | killed: display temporary 2x never persists and queued hold saves sample after release and speed change |
| `g20` | Compute scale before non-native return | equivalent (pure computation; excluded) |

**g20 equivalence.** `_aspectMode` is a plain enum field.
`AspectModeUtils.getScaleForMode` consists only of
`mode == AspectMode.cinemaZoom ? 4.0 / 3.0 : 1.0`; moving that read and pure
calculation before `platform is! mk.NativePlayer` cannot affect callers.
The existing non-native behaviour test passes in the sample. No guard or
application statement is changed to close an equivalent point.

## Phase 4 Step 1 — frozen production creation (2026-10-12)

Creation `9cae15e31`, following `61c081e33`; tested source hashes and commands in
`p4/step1/completion.json`. Exact formatted Step-T materialization is applied:
16 declarations into the 243-line `VpDisplayModeController`, its exact
14-member Host and frozen adapter; eager State constructor appends `_display`
after `_sleep` and `_skip`. Both HUD notifier allocations stay State-owned,
with original lifecycle ordering. All 33 retained occurrences are declared
substitutions; defaults and resume keep direct writes at the original positions.
No production bug fix or new seam.

| Check / transition | Result |
|---|---|
| Applied manifest | P4 current-tree, exhaustive ownership and retained order, imports, frozen scaffolding, historical destination protection: zero differences (`step1/current.txt`) |
| Optional commas / construction | Source bytes equal the proven Step-T formatted files; zero inserted/deleted optional commas; idempotent; zero formatting-introduced diagnostics; four inert initializers and 14 live Host readers (`tooling/optional-commas.json`, `tooling/construction-proof.json`) |
| Affected original-caller / guard tests | 189 successes, no failures/skips: all video-player tests, auto-next routing and theme source guards (`step1-affected.jsonl`); validating reader follows P4 without assertion edits |
| CI | Current/self → P4; P1 `--at 31a347ad2`, P2 `--at fc24e32ae`, P3 `--at 890df14d8`; analyzer P4 inventory preserves P1/P2/P3 mappings; five display test files registered; existing hook flag/fetch-depth 0/feature lists retained |
| Theme / architecture | All three source lists, rendered set and theme manifest extended; 1,665 migrated files and architecture negatives pass; existing exact bridge and 500-line caps apply |
| Sizes | Facade 17,766 → 17,592; dated shrink-only ratchet; controller 243; 2,996 files / 140 ratchets pass |
| Analyzer | Root/CI scoped 82, zero beyond frozen P4 maxima; root 1,777 → 1,778: one new controller import-order info only; outside identities/multiplicities exact; surviving warning allowlist unchanged |
| Format / scope | Exact CI format list passes; two declared application paths only; pubspec unchanged; isolated P4 parser/evidence routing |

Clean-tree gate follows this creation commit: full suite against accepted
`p4/step0-suite.jsonl`, all Dart/Kotlin self/current/history checks and both
release builds. Phone portrait seed, PiP restore and end-of-series manual
framing/rate/hold/orientation checklist remain pending.

## Phase 4 clean production gate (2026-10-12)

Tested clean creation `9cae15e31` against accepted Step-0 original-caller baseline
`5e08bb3a3`, with the same Flutter 3.44.8 / Dart 3.12.2 SDK and runner flags.
Gate evidence is entirely `refactor-evidence/vplayer/p4/`.

| Gate | Result / evidence |
|---|---|
| Complete suite | 12,970 success / 13 failure / 28 error / 20 skip; exact same identities and outcomes as `step0-suite.jsonl`; no additions, missing identities or changed outcomes (`p4-gate-suite.jsonl`, `gate/suite-delta.json`); official comparator PASS |
| Analyzer | Root/CI scoped 82, zero beyond frozen P4 inventory; root 1,778, expected +1 controller import-order info; outside identities/multiplicities exact and P1/P2/P3 maxima preserved (`gate/root-analyzer-delta.json`) |
| Format / sizes / boundaries | Exact CI format list PASS; 2,997 files / 140 ratchets, facade 17,592 / controller 243; 1,665 migrated files and architecture negatives PASS (`gate/fast-checks.json`) |
| Ownership / compatibility | All 32 commands PASS: 26 existing Dart manifest self-tests, P4 universal self-test including real configurations/negatives, P4 current, P1 `--at 31a347ad2`, P2 `--at fc24e32ae`, P3 `--at 890df14d8`, Kotlin checker self-test (`gate/compat-checks.json`) |
| Release builds | `nice -n 19 flutter build apk --release --no-pub` and `flutter build macos --release --no-pub` PASS on clean creation; artifact and macOS Dart AOT hashes in `gate/build-results.json`; no install/run |
| Parser / constraints | Explicit isolated parser per manifest, kernels deleted on copying, including nested self-tests; both evidence overrides active; exact two-file application scope, frozen formatted bytes, pubspec unchanged, trailers and original restore verified (`gate/parser-routing-audit.json`, `gate/constraints.json`) |

The 13 failures and 28 load errors remain pre-existing by identity; no allowlist
is expanded and no passing baseline test regresses. Claude's separate sample is
19/19 valid kills after the agreed g20 pure-computation equivalence; systematic
170-point matrix was recorded as 157 killed / three equivalent; vp-rev4
corrects it to 158 killed / two equivalent / nine dormant / one PiP
device-pending, as detailed below. No bug fixes, new seams or assertion weakening.

End-of-series manual checklist remains pending on phone, Android TV Flutter
player, tvOS and desktop: each aspect mode visibly changes framing (cinema zoom
included), selected speed changes rate and survives resume, phone hold gives
temporary 2×, phone orientation toggles, portrait-start seed and PiP restore of
the lock. Legacy cycle/menu fallback paths stay dormant. Stop after this gate.

## Phase 4 independent review closure — vp-rev4 (2026-10-12)

Review: No P1s, one P2. The earlier `field-aspect` equivalence was incorrect:
`_loadPlayerDefaults` awaits preferences while Focus already accepts key A;
aspect HUD has no readiness guard. Tests now hold the real preference load
instead of using the fixture's initialization-waiting mount for that window.
Application code is unchanged, including the original early-player failure.

| Initializer audit | Original observation / proof |
|---|---|
| `_aspectMode` | C39 key A renders Cover and crop-free icon before any player/controller/video exists. Zoom emits exactly one `LateInitializationError` for `_player`; not-ready resume save writes nothing. HUD clears at 1.5 s while storage remains held. Releasing cinema defaults overwrites the cycled value and applies zoom 0.415037; ready key A produces Contain, zoom 0.000000 and a real resume save at speed 1.0. Original initializer Cover mutant fails the HUD assertion: expected Cover, actual Fit Width. |
| `_playbackSpeed` | Remains non-equivalent: defaults do not assign it. Controls/video are readiness-gated; early save is blocked by `!_isReady`, and hold start returns on `!_isPlaying`. C39/C40 then expose speed 1.0 without rate calls, and C39 saves it after readiness. The 1.25 initializer mutant assertion-fails C40 (expected 1.0, actual 1.25); existing C16/C34 remain covered. |
| `_speedBeforeHold` | C40 real 600 ms pointer hold/release reaches the registered paused gesture callbacks before player creation. Null prior returns without rate/HUD/write/error. The 1.75 initializer mutant attempts early rate restore; C40 assertion fails on the captured framework error (expected null, actual uninitialized `_player`), rather than counting an uncaught-error-only run. |
| `_landscapeLocked` | Equivalent: synchronous `void initState` assigns `!_startsInPortrait` before orientation and `_initializePlayer`; the getter reads only a platform predicate and cached preference. First input dispatch follows build. False→true mutation passes both early cases, including initial landscape-left/right channel arguments, and original C29 pins the seed later. Phone portrait seed remains device-pending. |

Evidence `p4/vp-rev4/`: detached original HEAD `5e08bb3a3`, two-case control,
three assertion-failing initializer patches and landscape replay in
`mutation-results.json`; source restored. `initializer-audit.json` records
named original statement lines and source hashes; `coverage.json` updates
all 170 point fates and 40 case witnesses without rewriting original logs.
Original application matches `890df14d8`; the current production still matches
`794b1238c`. Both new cases live in existing registered display test files;
only the preference double is new, so CI test-path registration is unchanged.

Nice-19 serialized focused display suite: **40 successes**, zero failure/skip.
Changed Dart format and test analyzer pass; P4 current checker has **zero
differences**, with an isolated kernel-clean parser under `.dart_tool/vplayer_parser/`.
Commands, test/source hashes and parser invocation are in `vp-rev4/completion.json`.
No full-suite/build repeat for this test/docs-only review closure; the recorded
production gate remains at `9cae15e31`. No bug fix, production move, seam,
allowlisting, device command, push, merge or branch switch. Stop after commit.

## Phase 5 Step T — Trakt ownership tooling (2026-10-12)

Original `315028407`; tooling input `fc7196f78`. The P5 manifest is a complete
**draft**, with no production moves: 855 disjoint original spans, 841 retained,
12 moved and two patched (State constructor and whole skip Host adapter).
All 32 retained references are enumerated in
`p5/tooling/construction-and-references.json`; the skip adapter contributes
one exact counted receiver patch, and Simkl contributes two retained progress
substitutions. The original percentage documentation remains with its binder.

The frozen `VpTraktScrobblerHost` has 21 computed readers. The five relocated
initializers are inert: enabled/budget literal false; episode cache, last
scrobble action and heartbeat implicit null. Constructors assign only and read
no Host; the State eagerly appends Trakt after sleep, skip and display. The
294-line formatted destination exists only in evidence. No shared seek guard
or Simkl/MDBList declaration moves. History-derived protection covers all 13
P1–P4 destinations.

`check_dart_moves.py` adds opt-in exact projection for a patched whole facade
class, through the existing token-edit/parser implementation. `test_dart_trakt_moves.py`
rejects missing opt-in, wrong class/fate/count, undeclared skip-class changes,
wrong forwarding receiver, missing widget registrations, cached widget/index
values, wrong live identity, seek handover reordering/removal, late identity
reads, changed initial enablement and missing eager construction. Old manifest
behavior is unchanged. Complete raw/formatted splits and the exhaustive
all-retained original comparison have zero differences. All 26 existing Dart
self-tests, P5 universal/real-config tests, P1–P4 historical checks and Kotlin
historical/compiled self-test pass. Commands and logs: `p5/tooling/checks.json`.

Analyzer inventory preserves the earlier mappings and maxima; original root,
strict original and complete compiling probe record 82/151/84 occurrences.
The probe records the retained facade's now-unused Trakt import and new import
ordering info; formatting introduces none. `use_build_context_synchronously`
identities/multiplicities are unchanged by declaration. Full inventory and
format/token/optional-comma/idempotence evidence: `p5/tooling/`. Parser routing,
size and architecture checks pass. Failed development probes are archived and
uncredited. CI, theme lists and source-guard retargets wait for Step 1.

**Source guard retarget plan.** At Step 1, replace the percentage-reader slice
in `android_tv_mdblist_progress_source_test.dart` with validated per-declaration
reader calls for the Trakt, Simkl and MDBList readers, checking each live show
identity capture and rejection at its current location. Preserve the retained
TVMaze identity and rewatch assertions. The present source test remains intact.

## Phase 5 Step 0 — original Trakt characterization (2026-10-12)

Original application `315028407`, detached in `p5/step0/original`; Step T
commit `5d074e762`. Trakt only: Simkl and MDBList stay in the State and are
used solely to pin shared-percent forwarding, cache invalidation and seek
ordering. The source guard retarget remains the Step-T plan above for Step 1.

The isolate-wide delegating HTTP transport is installed before singleton
use, dispatches each send to the active case, and never delegates to a real
network. Synthetic storage credentials expire in 2100; profile/session and
snapshot-service caches reset between cases. Cipher barriers call the actual
cipher delegate. Storage/policy barriers delay delivery of actual decoded
payloads/immutable policies through the original await continuation, without
a production seam or private State call. The fixture adds only an optional
fake-player setup callback, needed before the original open publishes state.

75 new Trakt cases and the two existing skip integration cases pass
on the original. Every new case has a completed **assertion-failing** original
mutation witness matching its final case-file hash; supplementary final
replays are tagged `final-` in the witness ledger. Compile/load failures
and uncaught-error-only runs do not
count. Original declaration offsets, executable patch context, commands,
test/support hashes and full per-mutation JSONL/stderr are in
`p5/step0/points.json`, `mutation-results.json` and `mutations/`. Earlier
attempts remain in `mutation-results-first-pass.json`; invalid/comment-only
edits are excluded and replaced by executable, flow-valid mutations.

The systematic sweep covers all 12 moved declarations and all 32 retained
occurrences: **191 scope points**, 180 killed, 10 equivalent, 1 device pending.
An additional retained player-construction mutation proves the early
policy-await disposal case; it is reported separately from the Trakt scope.

| Moved declaration | Statement/branch/literal coverage |
|---|---|
| `_traktScrobbleEnabled` | `field-enabled` |
| `_launchTraktPercentSpent` | `field-budget` |
| `_traktEpisodeProgress` | `field-cache` |
| `_traktLastScrobbleAction` | `field-action` |
| `_traktHeartbeatTimer` | `field-timer` |
| `_initTraktScrobble` | `init-flag`, `init-id`, `init-type`, `init-movie`, `init-series`, `init-content`, `init-target`, `init-auth`, `init-mounted`, `init-playing`, `init-duration`, `init-start`, `init-heartbeat`, `init-swallow-storage`, `init-enable-assignment`, `init-start-marker` |
| `_traktProgress` | `progress-zero`, `progress-zero-value`, `progress-duration`, `progress-position`, `progress-units`, `progress-scale`, `progress-low`, `progress-high`, `progress-denominator` |
| `_traktScrobble` | `send-validation`, `send-enabled`, `send-id`, `send-capture`, `send-percent`, `send-start-action`, `send-pause-action`, `send-threshold`, `send-upper`, `send-convert`, `send-dedup`, `send-remember`, `send-dispatch`, `send-ready`, `send-api-0-call`, `send-api-0-id`, `send-api-0-progress`, `send-api-0-season`, `send-api-0-episode`, `send-api-0-type`, `send-api-1-call`, `send-api-1-id`, `send-api-1-progress`, `send-api-1-season`, `send-api-1-episode`, `send-api-1-type`, `send-api-2-call`, `send-api-2-id`, `send-api-2-progress`, `send-api-2-season`, `send-api-2-episode`, `send-api-2-type`, `send-break-0`, `send-break-1`, `send-break-2` |
| `_startTraktHeartbeat` | `beat-api-0-call`, `beat-api-0-id`, `beat-api-0-progress`, `beat-api-0-season`, `beat-api-0-episode`, `beat-api-0-type`, `beat-api-1-call`, `beat-api-1-id`, `beat-api-1-progress`, `beat-api-1-season`, `beat-api-1-episode`, `beat-api-1-type`, `beat-replace`, `beat-interval`, `beat-validation`, `beat-id`, `beat-playing`, `beat-duration`, `beat-capture`, `beat-percent`, `beat-threshold`, `beat-upper`, `beat-stop-action`, `beat-end`, `beat-precision`, `beat-stop-log`, `beat-start-action`, `beat-start-log`, `beat-enabled`, `beat-ready`, `beat-start-precision`, `beat-stop-return` |
| `_stopTraktHeartbeat` | `stop-cancel`, `stop-null` |
| `_traktScrobbleSeek` | `seek-api-0-call`, `seek-api-0-id`, `seek-api-0-progress`, `seek-api-0-season`, `seek-api-0-episode`, `seek-api-0-type`, `seek-api-1-call`, `seek-api-1-id`, `seek-api-1-progress`, `seek-api-1-season`, `seek-api-1-episode`, `seek-api-1-type`, `seek-deferred`, `seek-handover`, `seek-validation`, `seek-enabled`, `seek-id`, `seek-playing`, `seek-duration`, `seek-capture`, `seek-position`, `seek-scale`, `seek-low`, `seek-high`, `seek-threshold`, `seek-upper`, `seek-stop-action`, `seek-stop-beat`, `seek-start-action`, `seek-start-beat`, `seek-ready`, `seek-denominator` |
| `_currentEpisodeTraktPercent` | `snapshot-policy-content`, `snapshot-policy-mask`, `snapshot-identity`, `snapshot-bind`, `snapshot-cache`, `snapshot-guard`, `snapshot-late-guard`, `snapshot-assign`, `snapshot-series`, `snapshot-index`, `snapshot-episode`, `snapshot-season`, `snapshot-fallback`, `snapshot-fallback-season`, `snapshot-fallback-episode`, `snapshot-key`, `snapshot-guide`, `snapshot-id-null`, `snapshot-playlist-null`, `snapshot-bounds`, `snapshot-negative`, `snapshot-ep-null`, `snapshot-coordinates`, `snapshot-loop-break`, `snapshot-add-mounted`, `snapshot-add-generation`, `snapshot-read`, `snapshot-early-index` |

| Retained enclosing declaration | Individually classified occurrence (original line) |
|---|---|
| `initState` | `ref-01` (1683) |
| `_simklScrobble` | `ref-02` (2036) |
| `_startSimklHeartbeat` | `ref-03` (2089) |
| `_resumeTrackingAfterValidationGate` | `ref-04` (2295), `ref-05` (2294), `ref-06` (2295) |
| `_bindEpisodeTrackerProgressIdentity` | `ref-07` (2321) |
| `_bindPlayerInstanceSubscriptions` | `ref-08` (3651), `ref-09` (3658), `ref-10` (3650), `ref-11` (3659), `ref-12` (3652), `ref-13` (3660) |
| `_onPlaybackEnded` | `ref-14` (4988), `ref-15` (4987) |
| `_loadPlaylistIndexAttempt` | `ref-16` (10393), `ref-17` (10392) |
| `_onPipAction` | `ref-18` (11509) |
| `dispose` | `ref-19` (11703), `ref-20` (11701) |
| `_maybeRestoreResume` | `ref-21` (11976), `ref-22` (11977), `ref-23` (12004), `ref-24` (12103) |
| `_tvScrubCommit` | `ref-25` (12786) |
| `_buildTvControls` | `ref-26` (12855) |
| `_handleDoubleTap` | `ref-27` (13343) |
| `_onPanEnd` | `ref-28` (13441) |
| `build` | `ref-29` (14425), `ref-30` (14439), `ref-31` (14977) |
| `_VpSkipSegmentHostAdapter` | `ref-32` (17497) |

| Case | Original caller / asserted behavior | Assertion-failing original witness |
|---|---|---|
| C01 | Trakt missing coordinates cannot resume from malformed null snapshot keys | `snapshot-coordinates` |
| C02 | Trakt snapshot inner policy read rejects remote resume after outer policy has been captured | `final-snapshot-policy-mask` |
| C03 | Trakt single-file snapshot uses effective episode coordinates and caches the first read | `snapshot-read` |
| C04 | Trakt concurrent Simkl read changes shared identity and clears the outgoing Trakt cache | `final-ref-07` |
| C05 | Trakt early policy await follows incoming profile credentials for the still-mounted outgoing route | `final-ref-01` |
| C06 | Trakt dispose during policy preferences await starts no player heartbeat or send | `caller-init-mounted` |
| C07 | Trakt guide mask smart is reloaded after held local resume and late episode metadata | `ref-22` |
| C08 | Trakt guide mask local is reloaded after held local resume and late episode metadata | `snapshot-guide` |
| C09 | Trakt guide mask custom is reloaded after held local resume and late episode metadata | `snapshot-policy-content` |
| C10 | Trakt initialization flag gate prevents play seek heartbeat and dispose sends | `final-field-timer` |
| C11 | Trakt initialization identity gate prevents play seek heartbeat and dispose sends | `final-init-id` |
| C12 | Trakt initialization type gate prevents play seek heartbeat and dispose sends | `final-init-type` |
| C13 | Trakt initialization target gate prevents play seek heartbeat and dispose sends | `final-init-target` |
| C14 | Trakt initialization credential gate prevents play seek heartbeat and dispose sends | `final-init-auth` |
| C15 | Trakt initialization custom gate prevents play seek heartbeat and dispose sends | `final-init-content` |
| C16 | Trakt initialization coordinates gate prevents play seek heartbeat and dispose sends | `send-ready` |
| C17 | Trakt held auth initialization playing completion samples live state | `init-heartbeat` |
| C18 | Trakt held auth initialization paused completion samples live state | `final-ref-01` |
| C19 | Trakt held auth initialization duration completion samples live state | `final-ref-01` |
| C20 | Trakt held auth completion above eighty sends stop without arming heartbeat | `init-start-marker` |
| C21 | Trakt held initialization dispose completion has no outgoing send | `final-ref-01` |
| C22 | Trakt held initialization profile completion has no outgoing send | `final-ref-01` |
| C23 | Trakt auth storage failure escapes initialization without enabling sends | `final-ref-01` |
| C24 | Trakt seek samples target clamps progress and rejects paused or unknown duration | `final-seek-playing` |
| C25 | Trakt progress samples held unlanded resume rather than the raw restart position | `final-ref-01` |
| C26 | Trakt heartbeat live gates paused retain the original timer without sending or logging a checkpoint | `ref-10` |
| C27 | Trakt heartbeat live gates duration retain the original timer without sending or logging a checkpoint | `ref-10` |
| C28 | Trakt heartbeat live gates coordinates retain the original timer without sending or logging a checkpoint | `ref-10` |
| C29 | Trakt heartbeat live gates identity retain the original timer without sending or logging a checkpoint | `ref-10` |
| C30 | Trakt progress zero duration or position uses original clamped percent | `final-ref-01` |
| C31 | Trakt progress negative duration or position uses original clamped percent | `final-ref-01` |
| C32 | Trakt progress beyond duration or position uses original clamped percent | `final-ref-01` |
| C33 | Trakt progress subsecond duration or position uses original clamped percent | `progress-duration` |
| C34 | Trakt live widget identity and media type drive pause and heartbeat without reinitializing State | `beat-id` |
| C35 | Trakt unresolved episode creates no latent seek or start heartbeat when coordinates arrive later | `send-ready` |
| C36 | Trakt shared percent through Simkl pause retains current progress | `final-ref-02` |
| C37 | Trakt shared percent through Simkl heartbeat retains current progress | `final-ref-03` |
| C38 | Trakt seek rearms heartbeat and restores start dedup after a watched stop | `seek-start-action` |
| C39 | Trakt protocol episode start pause stop bodies and duplicate edges | `init-enable-assignment` |
| C40 | Trakt protocol movie start pause stop bodies and duplicate edges | `init-enable-assignment` |
| C41 | Trakt pause transition at 80 percent keeps strict watched threshold | `ref-09` |
| C42 | Trakt playing transition at 80 percent keeps strict watched threshold | `send-threshold` |
| C43 | Trakt user seek at 80 percent bypasses dedup and owns heartbeat | `seek-denominator` |
| C44 | Trakt pause transition at 81 percent keeps strict watched threshold | `ref-09` |
| C45 | Trakt playing transition at 81 percent keeps strict watched threshold | `send-upper` |
| C46 | Trakt user seek at 81 percent bypasses dedup and owns heartbeat | `seek-stop-action` |
| C47 | Trakt heartbeat interval replaces previous timer bypasses dedup then stops above eighty | `beat-stop-return` |
| C48 | Trakt pause cancels the heartbeat with exact final event | `ref-13` |
| C49 | Trakt EOF cancels the heartbeat with exact final event | `ref-14` |
| C50 | Trakt dispose cancels the heartbeat with exact final event | `ref-19` |
| C51 | Trakt heartbeat restores start dedup after an implicit stop with a live timer | `ref-10` |
| C52 | Trakt failed status send spends dedup before completion and seek retries | `ref-09` |
| C53 | Trakt failed throw send spends dedup before completion and seek retries | `ref-09` |
| C54 | Trakt failed held send spends dedup before completion and seek retries | `ref-09` |
| C55 | Trakt seek target before landing is sent immediately without sampling the old position | `seek-position` |
| C56 | Trakt disabled user key cancels deferred Stremio startup offset before duration arrives | `seek-deferred` |
| C57 | Trakt disabled key releases held resume target before its early return | `seek-handover` |
| C58 | Trakt validation-active key releases held resume target before its early return | `seek-handover` |
| C59 | Trakt keyboard rewind seek sends the clamped target | `ref-29` |
| C60 | Trakt double tap left seek reaches the original tracking caller | `ref-27` |
| C61 | Trakt keyboard forward seek sends the clamped target | `ref-30` |
| C62 | Trakt double tap right seek reaches the original tracking caller | `ref-27` |
| C63 | Trakt horizontal pan completion sends the displayed seek target | `ref-28` |
| C64 | Trakt TV scope seek forwards its target into the tracker | `ref-26` |
| C65 | Trakt TV scrub confirm sends progress while the native pause is still suspended | `ref-25` |
| C66 | Trakt playlist switch stops outgoing scrobble and timer before a held incoming open | `ref-16` |
| C67 | Trakt snapshot missing episode rejects a changed public guide model during storage | `final-snapshot-ep-null` |
| C68 | Trakt launch promise is spent once and later playlist items use their own snapshot | `snapshot-series` |
| C69 | Trakt suspended snapshot episode reads current coordinates and preserves original identity guard | `snapshot-early-index` |
| C70 | Trakt suspended snapshot show reads current coordinates and preserves original identity guard | `final-snapshot-bind` |
| C71 | Trakt suspended snapshot A-B-A reads current coordinates and preserves original identity guard | `final-snapshot-add-generation` |
| C72 | Trakt suspended snapshot profile reads current coordinates and preserves original identity guard | `snapshot-index` |
| C73 | Trakt suspended snapshot dispose reads current coordinates and preserves original identity guard | `final-snapshot-add-mounted` |
| C74 | Trakt startup validation release sends start and arms heartbeat after auth completed inside the gate | `ref-01` |
| C75 | Trakt manual validation suppresses seek heartbeat and disposal scrobble despite live stream events | `send-validation` |
| C76 | skip publishes clock before seek, queues tracking before haptic and preserves remote stop order | `ref-32` |
| C77 | skip tracker seek order arms Trakt heartbeat before Simkl | `ref-01` |

| Mutation point | Original statement/branch/literal → mutation | Result / case |
|---|---|---|
| `field-enabled` (_traktScrobbleEnabled:1483) | `false` → `true` | killed: C17, C18, C19 |
| `field-budget` (_launchTraktPercentSpent:1486) | `false` → `true` | killed: C68 |
| `field-cache` (_traktEpisodeProgress:1489) | `_traktEpisodeProgress;` → `_traktEpisodeProgress = {};` | equivalent: All cache reads follow the shared identity binder; the initially null identity guarantees the first binder resets all three caches before any read. Simkl/MDBList can bind first but perform the same reset. |
| `field-action` (_traktLastScrobbleAction:1490) | `_traktLastScrobbleAction;` → `_traktLastScrobbleAction = 'start';` | killed: C39, C40 |
| `field-timer` (_traktHeartbeatTimer:1491) | `Timer? _traktHeartbeatTimer;` → `late Timer? _traktHeartbeatTimer;` | killed: C10 |
| `init-flag` (_initTraktScrobble:1740) | `if (!widget.traktScrobble) return;` → `// flag gate removed` | killed: C10 |
| `init-id` (_initTraktScrobble:1741) | `if (widget.contentImdbId == null) return;` → `// identity gate removed` | killed: C11 |
| `init-type` (_initTraktScrobble:1742) | `if (widget.contentType != 'movie' && widget.contentType != 'series') return;` → `// type gate removed` | killed: C12 |
| `init-movie` (_initTraktScrobble:1742) | `widget.contentType != 'movie'` → `true` | killed: C40 |
| `init-series` (_initTraktScrobble:1742) | `widget.contentType != 'series'` → `true` | killed: C39 |
| `init-content` (_initTraktScrobble:1744) | `_effectiveContentImdbId` → `null` | killed: C15 |
| `init-target` (_initTraktScrobble:1747) | `policy.scrobbles(TrackingSource.trakt)` → `true` | killed: C13 |
| `init-auth` (_initTraktScrobble:1748) | `await TraktService.instance.isAuthenticated()` → `true` | killed: C14 |
| `init-mounted` (_initTraktScrobble:1749) | `if (!mounted) return;` → `// mounted gate removed` | killed: C21 |
| `init-playing` (_initTraktScrobble:1751) | `_traktScrobbleEnabled && _isPlaying && _duration > Duration.zero` → `_traktScrobbleEnabled && _duration > Duration.zero` | killed: C18 |
| `init-duration` (_initTraktScrobble:1751) | `_traktScrobbleEnabled && _isPlaying && _duration > Duration.zero` → `_traktScrobbleEnabled && _isPlaying` | killed: C19 |
| `init-start` (_initTraktScrobble:1752) | `_traktScrobble('start');` → `// initial start removed` | killed: C39, C40 |
| `init-heartbeat` (_initTraktScrobble:1754) | `_startTraktHeartbeat();` → `// initial heartbeat removed` | killed: C17 |
| `progress-zero` (_traktProgress:1784) | `if (_duration.inMilliseconds <= 0) return 0.0;` → `// zero-duration guard removed` | killed: C30 |
| `progress-zero-value` (_traktProgress:1784) | `return 0.0;` → `return 1.0;` | killed: C30 |
| `progress-duration` (_traktProgress:1784) | `_duration.inMilliseconds` → `_duration.inSeconds` | killed: C33 |
| `progress-position` (_traktProgress:1785) | `_persistablePosition.inMilliseconds` → `_position.inMilliseconds` | killed: C25 |
| `progress-units` (_traktProgress:1785) | `_persistablePosition.inMilliseconds` → `_persistablePosition.inSeconds` | killed: C39, C40 |
| `progress-scale` (_traktProgress:1787) | `100)` → `10)` | killed: C39, C40 |
| `progress-low` (_traktProgress:1788) | `0.0, 100.0` → `1.0, 100.0` | killed: C31 |
| `progress-high` (_traktProgress:1788) | `0.0, 100.0` → `0.0, 90.0` | killed: C32 |
| `send-validation` (_traktScrobble:1818) | `if (_validationGateActive) return;` → `// validation guard removed` | killed: C75 |
| `send-enabled` (_traktScrobble:1819) | `!_traktScrobbleEnabled \|\| widget.contentImdbId == null` → `widget.contentImdbId == null` | killed: C10 |
| `send-id` (_traktScrobble:1819) | `!_traktScrobbleEnabled \|\| widget.contentImdbId == null` → `!_traktScrobbleEnabled` | killed: C34 |
| `send-capture` (_traktScrobble:1820) | `final imdbId = widget.contentImdbId!;` → `final imdbId = 'tt5999999';` | killed: C39, C40 |
| `send-percent` (_traktScrobble:1821) | `final progress = _traktProgress();` → `final progress = 0.0;` | killed: C39, C40 |
| `send-start-action` (_traktScrobble:1831) | `action == 'start'` → `action == 'ignored'` | killed: C45 |
| `send-pause-action` (_traktScrobble:1831) | `action == 'pause'` → `action == 'ignored'` | killed: C44 |
| `send-threshold` (_traktScrobble:1831) | `&& progress > 80` → `&& progress >= 80` | killed: C42 |
| `send-upper` (_traktScrobble:1831) | `&& progress > 80` → `&& progress > 81` | killed: C45 |
| `send-convert` (_traktScrobble:1832) | `action = 'stop';` → `action = 'start';` | killed: C45 |
| `send-dedup` (_traktScrobble:1834) | `if (_traktLastScrobbleAction == action) return;` → `// dedup removed` | killed: C39, C40, C52, C53, C54 |
| `send-remember` (_traktScrobble:1835) | `_traktLastScrobbleAction = action;` → `// last action removed` | killed: C39, C40, C52, C53, C54 |
| `send-dispatch` (_traktScrobble:1836) | `switch (action)` → `switch ('stop')` | killed: C39, C40 |
| `send-ready` (_traktScrobble:1823) | `if (!TraktService.isScrobbleReady( contentType: widget.contentType, season: se.season, …` → `// ready guard removed` | killed: C16, C35 |
| `send-api-0-call` (_traktScrobble:1838) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `` | killed: C39, C40 |
| `send-api-0-id` (_traktScrobble:1838) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( 'tt5999999', progress, season: se.season, episode:…` | killed: C39, C40 |
| `send-api-0-progress` (_traktScrobble:1838) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, 0.0, season: se.season, episode: se.episod…` | killed: C39, C40 |
| `send-api-0-season` (_traktScrobble:1838) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, progress, season: 99, episode: se.episode,…` | killed: C39 |
| `send-api-0-episode` (_traktScrobble:1838) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: 99, …` | killed: C39 |
| `send-api-0-type` (_traktScrobble:1838) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` | killed: C39 |
| `send-api-1-call` (_traktScrobble:1847) | `TraktService.instance.scrobblePause( imdbId, progress, season: se.season, episode: se.e…` → `` | killed: C39, C40 |
| `send-api-1-id` (_traktScrobble:1847) | `TraktService.instance.scrobblePause( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobblePause( 'tt5999999', progress, season: se.season, episode:…` | killed: C39, C40 |
| `send-api-1-progress` (_traktScrobble:1847) | `TraktService.instance.scrobblePause( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobblePause( imdbId, 0.0, season: se.season, episode: se.episod…` | killed: C39, C40 |
| `send-api-1-season` (_traktScrobble:1847) | `TraktService.instance.scrobblePause( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobblePause( imdbId, progress, season: 99, episode: se.episode,…` | killed: C39 |
| `send-api-1-episode` (_traktScrobble:1847) | `TraktService.instance.scrobblePause( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobblePause( imdbId, progress, season: se.season, episode: 99, …` | killed: C39 |
| `send-api-1-type` (_traktScrobble:1847) | `TraktService.instance.scrobblePause( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobblePause( imdbId, progress, season: se.season, episode: se.e…` | killed: C39 |
| `send-api-2-call` (_traktScrobble:1856) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `` | killed: C39, C40 |
| `send-api-2-id` (_traktScrobble:1856) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( 'tt5999999', progress, season: se.season, episode: …` | killed: C39, C40 |
| `send-api-2-progress` (_traktScrobble:1856) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, 0.0, season: se.season, episode: se.episode…` | killed: C39, C40 |
| `send-api-2-season` (_traktScrobble:1856) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, progress, season: 99, episode: se.episode, …` | killed: C39 |
| `send-api-2-episode` (_traktScrobble:1856) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: 99, c…` | killed: C39 |
| `send-api-2-type` (_traktScrobble:1856) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` | killed: C39 |
| `send-break-0` (_traktScrobble:1845) | `break;` → `// implicit break` | equivalent: Dart switch statements implicitly terminate non-empty cases; no fallthrough. Replay required. |
| `send-break-1` (_traktScrobble:1854) | `break;` → `// implicit break` | equivalent: Dart switch statements implicitly terminate non-empty cases; no fallthrough. Replay required. |
| `send-break-2` (_traktScrobble:1863) | `break;` → `// implicit break` | equivalent: Dart switch statements implicitly terminate non-empty cases; no fallthrough. Replay required. |
| `beat-api-0-call` (_startTraktHeartbeat:1890) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `` | killed: C47 |
| `beat-api-0-id` (_startTraktHeartbeat:1890) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( 'tt5999999', progress, season: se.season, episode: …` | killed: C47 |
| `beat-api-0-progress` (_startTraktHeartbeat:1890) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, 0.0, season: se.season, episode: se.episode…` | killed: C47 |
| `beat-api-0-season` (_startTraktHeartbeat:1890) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, progress, season: 99, episode: se.episode, …` | killed: C47 |
| `beat-api-0-episode` (_startTraktHeartbeat:1890) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: 99, c…` | killed: C47 |
| `beat-api-0-type` (_startTraktHeartbeat:1890) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` | killed: C47 |
| `beat-api-1-call` (_startTraktHeartbeat:1905) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `` | killed: C47 |
| `beat-api-1-id` (_startTraktHeartbeat:1905) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( 'tt5999999', progress, season: se.season, episode:…` | killed: C47 |
| `beat-api-1-progress` (_startTraktHeartbeat:1905) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, 0.0, season: se.season, episode: se.episod…` | killed: C47 |
| `beat-api-1-season` (_startTraktHeartbeat:1905) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, progress, season: 99, episode: se.episode,…` | killed: C47 |
| `beat-api-1-episode` (_startTraktHeartbeat:1905) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: 99, …` | killed: C47 |
| `beat-api-1-type` (_startTraktHeartbeat:1905) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` | killed: C47 |
| `seek-api-0-call` (_traktScrobbleSeek:1968) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `` | killed: C46 |
| `seek-api-0-id` (_traktScrobbleSeek:1968) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( 'tt5999999', progress, season: se.season, episode: …` | killed: C46 |
| `seek-api-0-progress` (_traktScrobbleSeek:1968) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, 0.0, season: se.season, episode: se.episode…` | killed: C46 |
| `seek-api-0-season` (_traktScrobbleSeek:1968) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, progress, season: 99, episode: se.episode, …` | killed: C46 |
| `seek-api-0-episode` (_traktScrobbleSeek:1968) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: 99, c…` | killed: C46 |
| `seek-api-0-type` (_traktScrobbleSeek:1968) | `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` → `TraktService.instance.scrobbleStop( imdbId, progress, season: se.season, episode: se.ep…` | killed: C46 |
| `seek-api-1-call` (_traktScrobbleSeek:1978) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `` | killed: C43 |
| `seek-api-1-id` (_traktScrobbleSeek:1978) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( 'tt5999999', progress, season: se.season, episode:…` | killed: C43 |
| `seek-api-1-progress` (_traktScrobbleSeek:1978) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, 0.0, season: se.season, episode: se.episod…` | killed: C43 |
| `seek-api-1-season` (_traktScrobbleSeek:1978) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, progress, season: 99, episode: se.episode,…` | killed: C43 |
| `seek-api-1-episode` (_traktScrobbleSeek:1978) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: 99, …` | killed: C43 |
| `seek-api-1-type` (_traktScrobbleSeek:1978) | `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` → `TraktService.instance.scrobbleStart( imdbId, progress, season: se.season, episode: se.e…` | killed: C43 |
| `beat-replace` (_startTraktHeartbeat:1869) | `_traktHeartbeatTimer?.cancel();` → `// replacement cancel removed` | killed: C47 |
| `beat-interval` (_startTraktHeartbeat:1870) | `minutes: 2` → `minutes: 1` | killed: C47 |
| `beat-validation` (_startTraktHeartbeat:1871) | `_validationGateActive \|\|` → `false \|\|` | killed: C75 |
| `beat-id` (_startTraktHeartbeat:1873) | `widget.contentImdbId == null` → `false` | killed: C34 |
| `beat-playing` (_startTraktHeartbeat:1876) | `!_isPlaying \|\| _duration.inMilliseconds <= 0` → `_duration.inMilliseconds <= 0` | killed: C26 |
| `beat-duration` (_startTraktHeartbeat:1876) | `!_isPlaying \|\| _duration.inMilliseconds <= 0` → `!_isPlaying` | killed: C27 |
| `beat-capture` (_startTraktHeartbeat:1877) | `final imdbId = widget.contentImdbId!;` → `final imdbId = 'tt5999999';` | killed: C47 |
| `beat-percent` (_startTraktHeartbeat:1878) | `final progress = _traktProgress();` → `final progress = 0.0;` | killed: C47 |
| `beat-threshold` (_startTraktHeartbeat:1888) | `progress > 80` → `progress >= 80` | killed: C47 |
| `beat-upper` (_startTraktHeartbeat:1888) | `progress > 80` → `progress > 81` | killed: C47 |
| `beat-stop-action` (_startTraktHeartbeat:1889) | `_traktLastScrobbleAction = 'stop';` → `// stop marker removed` | killed: C47 |
| `beat-end` (_startTraktHeartbeat:1900) | `_stopTraktHeartbeat();` → `// end heartbeat removed` | killed: C47 |
| `beat-precision` (_startTraktHeartbeat:1898) | `toStringAsFixed(1)` → `toStringAsFixed(2)` | killed: C47 |
| `beat-stop-log` (_startTraktHeartbeat:1898) | `Trakt: Heartbeat stop at` → `Trakt: Changed stop at` | killed: C47 |
| `beat-start-action` (_startTraktHeartbeat:1904) | `_traktLastScrobbleAction = 'start';` → `// start marker removed` | killed: C51 |
| `beat-start-log` (_startTraktHeartbeat:1913) | `Trakt: Heartbeat scrobble at` → `Trakt: Changed start at` | killed: C47 |
| `beat-enabled` (_startTraktHeartbeat:1872) | `!_traktScrobbleEnabled \|\|` → `false \|\|` | equivalent: Only enabled start/seek/init paths install a heartbeat; enabled is assigned once during init, no later false assignment. Replay across all callers. |
| `beat-ready` (_startTraktHeartbeat:1880) | `if (!TraktService.isScrobbleReady( contentType: widget.contentType, season: se.season, …` → `// ready guard removed` | killed: C28 |
| `stop-cancel` (_stopTraktHeartbeat:1919) | `_traktHeartbeatTimer?.cancel();` → `// timer cancel removed` | killed: C50 |
| `stop-null` (_stopTraktHeartbeat:1920) | `_traktHeartbeatTimer = null;` → `// canceled pointer retained` | equivalent: All readers only cancel/overwrite this pointer; repeated cancellation is idempotent, a canceled timer never fires. Replay required. |
| `seek-deferred` (_traktScrobbleSeek:1946) | `_stremioTvStartupSeek.cancel();` → `// deferred cancel removed` | killed: C56 |
| `seek-handover` (_traktScrobbleSeek:1947) | `_resumeWriteGuard.noteUserSeek();` → `// handover removed` | killed: C57, C58 |
| `seek-validation` (_traktScrobbleSeek:1948) | `if (_validationGateActive) return;` → `// validation guard removed` | killed: C75 |
| `seek-enabled` (_traktScrobbleSeek:1949) | `!_traktScrobbleEnabled \|\| widget.contentImdbId == null` → `widget.contentImdbId == null` | killed: C10 |
| `seek-id` (_traktScrobbleSeek:1949) | `!_traktScrobbleEnabled \|\| widget.contentImdbId == null` → `!_traktScrobbleEnabled` | killed: C34 |
| `seek-playing` (_traktScrobbleSeek:1950) | `!_isPlaying \|\| _duration.inMilliseconds <= 0` → `_duration.inMilliseconds <= 0` | killed: C24 |
| `seek-duration` (_traktScrobbleSeek:1950) | `!_isPlaying \|\| _duration.inMilliseconds <= 0` → `!_isPlaying` | killed: C24 |
| `seek-capture` (_traktScrobbleSeek:1951) | `final imdbId = widget.contentImdbId!;` → `final imdbId = 'tt5999999';` | killed: C43, C46 |
| `seek-position` (_traktScrobbleSeek:1953) | `seekTarget.inMilliseconds` → `_position.inMilliseconds` | killed: C55 |
| `seek-scale` (_traktScrobbleSeek:1953) | `100).clamp` → `10).clamp` | killed: C43, C46 |
| `seek-low` (_traktScrobbleSeek:1954) | `0.0, 100.0` → `1.0, 100.0` | killed: C24 |
| `seek-high` (_traktScrobbleSeek:1954) | `0.0, 100.0` → `0.0, 90.0` | killed: C24 |
| `seek-threshold` (_traktScrobbleSeek:1966) | `progress > 80` → `progress >= 80` | killed: C43 |
| `seek-upper` (_traktScrobbleSeek:1966) | `progress > 80` → `progress > 81` | killed: C46 |
| `seek-stop-action` (_traktScrobbleSeek:1967) | `_traktLastScrobbleAction = 'stop';` → `// stop marker removed` | killed: C46 |
| `seek-stop-beat` (_traktScrobbleSeek:1975) | `_stopTraktHeartbeat();` → `// stop heartbeat removed` | killed: C46 |
| `seek-start-action` (_traktScrobbleSeek:1977) | `_traktLastScrobbleAction = 'start';` → `// start marker removed` | killed: C38 |
| `seek-start-beat` (_traktScrobbleSeek:1985) | `_startTraktHeartbeat();` → `// start heartbeat removed` | killed: C38 |
| `seek-ready` (_traktScrobbleSeek:1958) | `if (!TraktService.isScrobbleReady( contentType: widget.contentType, season: se.season, …` → `// ready guard removed` | killed: C35 |
| `snapshot-policy-content` (_currentEpisodeTraktPercent:2328) | `_effectiveContentImdbId` → `null` | killed: C09 |
| `snapshot-policy-mask` (_currentEpisodeTraktPercent:2330) | `if (!forGuide && !policy.progressFrom(TrackingSource.trakt)) return null;` → `// mask removed` | killed: C02 |
| `snapshot-identity` (_currentEpisodeTraktPercent:2331) | `final imdbId = _currentSeriesImdbId;` → `final imdbId = 'tt5999999';` | killed: C03 |
| `snapshot-bind` (_currentEpisodeTraktPercent:2333) | `_bindEpisodeTrackerProgressIdentity(imdbId);` → `// bind removed` | killed: C70 |
| `snapshot-cache` (_currentEpisodeTraktPercent:2338) | `if (_traktEpisodeProgress == null)` → `if (true)` | killed: C68 |
| `snapshot-guard` (_currentEpisodeTraktPercent:2343) | `if (_episodeTrackerProgressImdbId != imdbId) return null;` → `// stale guard removed` | killed: C70 |
| `snapshot-late-guard` (_currentEpisodeTraktPercent:2343) | `_episodeTrackerProgressImdbId != imdbId` → `_episodeTrackerProgressImdbId != _currentSeriesImdbId` | killed: C70 |
| `snapshot-assign` (_currentEpisodeTraktPercent:2344) | `_traktEpisodeProgress = loaded;` → `_traktEpisodeProgress = {};` | killed: C68 |
| `snapshot-series` (_currentEpisodeTraktPercent:2350) | `seriesPlaylist != null && seriesPlaylist.isSeries` → `seriesPlaylist != null && !seriesPlaylist.isSeries` | killed: C68 |
| `snapshot-index` (_currentEpisodeTraktPercent:2361) | `e.originalIndex == _currentIndex` → `e.originalIndex == 0` | killed: C68, C72 |
| `snapshot-episode` (_currentEpisodeTraktPercent:2368) | `episode = ep.seriesInfo.episode;` → `episode = 99;` | killed: C68 |
| `snapshot-season` (_currentEpisodeTraktPercent:2367) | `season = ep.seriesInfo.season;` → `season = 99;` | killed: C68 |
| `snapshot-fallback` (_currentEpisodeTraktPercent:2369) | `_effectiveContentType == 'series'` → `_effectiveContentType == 'movie'` | killed: C03 |
| `snapshot-fallback-season` (_currentEpisodeTraktPercent:2373) | `season = _effectiveContentSeason;` → `season = 99;` | killed: C03 |
| `snapshot-fallback-episode` (_currentEpisodeTraktPercent:2374) | `episode = _effectiveContentEpisode;` → `episode = 99;` | killed: C03 |
| `snapshot-key` (_currentEpisodeTraktPercent:2378) | `'${season}_$episode'` → `'${episode}_$season'` | killed: C03 |
| `snapshot-guide` (_currentEpisodeTraktPercent:2379) | `return forGuide ? policy.guideProgressFrom(TrackingSource.trakt, percent) : percent;` → `return percent;` | killed: C08, C09 |
| `snapshot-id-null` (_currentEpisodeTraktPercent:2332) | `if (imdbId == null) return null;` → `if (imdbId == null) throw StateError('synthetic missing identity');` | killed: C11 |
| `snapshot-playlist-null` (_currentEpisodeTraktPercent:2352) | `playlist == null \|\|` → `false \|\|` | equivalent: SeriesPlaylist is created only from the non-null active playlist; synthetic guides use a separate field. All assignment sites retained. |
| `snapshot-bounds` (_currentEpisodeTraktPercent:2354) | `_currentIndex >= playlist.length` → `false` | equivalent: Series model creation uses only valid original playlist indices; an out-of-range current index cannot match a row and the later ep==null guard returns null. A replacement can temporarily retain the outgoing index, but invalidates/rebuilds the model first. No asynchronous gap inside the scan. |
| `snapshot-negative` (_currentEpisodeTraktPercent:2353) | `_currentIndex < 0 \|\|` → `false \|\|` | equivalent: Launch indices are clamped and navigation validates indices; production-created active series rows have non-negative originalIndex. Any negative value would fail the row scan and the later ep==null guard. Synthetic absent-guide rows are held separately. |
| `snapshot-ep-null` (_currentEpisodeTraktPercent:2366) | `if (ep == null) return null;` → `ep ??= seriesPlaylist.allEpisodes.first;` | killed: C67 |
| `snapshot-coordinates` (_currentEpisodeTraktPercent:2376) | `if (season == null \|\| episode == null) return null;` → `// missing coordinate guard removed` | killed: C01 |
| `snapshot-loop-break` (_currentEpisodeTraktPercent:2363) | `break;` → `// continue scanning` | equivalent: Original fromPlaylistEntries assigns distinct immutable originalIndex values from unique validIndices. TVMaze metadata changes seriesInfo, not indices; no original caller appends a duplicate active row. Continuing the synchronous scan cannot replace the matching row. |
| `init-swallow-storage` (_initTraktScrobble:1743) | `final policy = (await TrackingSourcePolicy.load()).forContent( _effectiveContentImdbId,…` → `try { final policy = (await TrackingSourcePolicy.load()).forContent( _effectiveContentI…` | killed: C23 |
| `snapshot-add-mounted` (_currentEpisodeTraktPercent:2344) | `_traktEpisodeProgress = loaded;` → `if (!mounted) return null; _traktEpisodeProgress = loaded;` | killed: C73 |
| `snapshot-add-generation` (_currentEpisodeTraktPercent:2331) | `final imdbId = _currentSeriesImdbId;` → `final capturedNavigation = _episodeNavigationGeneration; final imdbId = _currentSeriesI…` | killed: C71 |
| `beat-start-precision` (_startTraktHeartbeat:1913) | `toStringAsFixed(1)` → `toStringAsFixed(2)` | killed: C47 |
| `init-enable-assignment` (_initTraktScrobble:1747) | `policy.scrobbles(TrackingSource.trakt) &&` → `false &&` | killed: C39, C40 |
| `init-start-marker` (_initTraktScrobble:1753) | `if (_traktLastScrobbleAction == 'start')` → `if (true)` | killed: C20 |
| `progress-denominator` (_traktProgress:1786) | `_duration.inMilliseconds` → `_duration.inSeconds` | killed: C33 |
| `seek-denominator` (_traktScrobbleSeek:1953) | `_duration.inMilliseconds * 100` → `_duration.inSeconds * 100` | killed: C43, C46 |
| `beat-stop-return` (_startTraktHeartbeat:1900) | `_stopTraktHeartbeat(); return;` → `_stopTraktHeartbeat();` | killed: C47 |
| `snapshot-read` (_currentEpisodeTraktPercent:2378) | `_traktEpisodeProgress!['${season}_$episode']` → `0.0` | killed: C03 |
| `snapshot-early-index` (_currentEpisodeTraktPercent:2331) | `final imdbId = _currentSeriesImdbId;` → `final capturedIndex = _currentIndex; final imdbId = _currentSeriesImdbId;` | killed: C69 |
| `caller-init-mounted` (_initializePlayer:3129) | `if (!mounted) return;` → `// caller mounted gate removed` | killed: C06 |
| `ref-01` (initState:1683) | `_initTraktScrobble();` → `` | killed: C05, C17, C18, C19, C21, C22, C23, C25, C26, C27, C28, C29, C30, C31, C32, C35, C39, C40, C41, C42, C43, C44, C45, C46, C47, C48, C49, C50, C51, C52, C53, C54, C55, C58, C68, C74, C75, C77 |
| `ref-02` (_simklScrobble:2036) | `_traktProgress()` → `0.0` | killed: C36 |
| `ref-03` (_startSimklHeartbeat:2089) | `_traktProgress()` → `0.0` | killed: C37 |
| `ref-04` (_resumeTrackingAfterValidationGate:2295) | `_traktLastScrobbleAction` → `'stop'` | killed: C74 |
| `ref-05` (_resumeTrackingAfterValidationGate:2294) | `_traktScrobble('start');` → `` | killed: C58, C74 |
| `ref-06` (_resumeTrackingAfterValidationGate:2295) | `_startTraktHeartbeat();` → `` | killed: C74 |
| `ref-07` (_bindEpisodeTrackerProgressIdentity:2321) | `_traktEpisodeProgress = null;` → `` | killed: C04 |
| `ref-08` (_bindPlayerInstanceSubscriptions:3651) | `_traktLastScrobbleAction` → `'stop'` | killed: C47 |
| `ref-09` (_bindPlayerInstanceSubscriptions:3658) | `_traktLastScrobbleAction` → `'stop'` | killed: C39, C40, C41, C42, C44, C45, C52, C53, C54 |
| `ref-10` (_bindPlayerInstanceSubscriptions:3650) | `_traktScrobble('start');` → `` | killed: C26, C27, C28, C29, C42, C45, C51 |
| `ref-11` (_bindPlayerInstanceSubscriptions:3659) | `_traktScrobble('pause');` → `` | killed: C39, C40, C41, C42, C44, C45, C52, C53, C54 |
| `ref-12` (_bindPlayerInstanceSubscriptions:3652) | `_startTraktHeartbeat();` → `` | killed: C47 |
| `ref-13` (_bindPlayerInstanceSubscriptions:3660) | `_stopTraktHeartbeat();` → `` | killed: C48 |
| `ref-14` (_onPlaybackEnded:4988) | `_traktScrobble('stop');` → `` | killed: C49 |
| `ref-15` (_onPlaybackEnded:4987) | `_stopTraktHeartbeat();` → `` | killed: C49 |
| `ref-16` (_loadPlaylistIndexAttempt:10393) | `_traktScrobble('stop');` → `` | killed: C66 |
| `ref-17` (_loadPlaylistIndexAttempt:10392) | `_stopTraktHeartbeat();` → `` | killed: C66 |
| `ref-18` (_onPipAction:11509) | `_traktScrobbleSeek(position);` → `` | device_pending: Only installed behind sealed Android/iOS platform predicates; no platform seam. Human PiP seek checklist. |
| `ref-19` (dispose:11703) | `_traktScrobble('stop');` → `` | killed: C39, C40, C50 |
| `ref-20` (dispose:11701) | `_stopTraktHeartbeat();` → `` | killed: C50 |
| `ref-21` (_maybeRestoreResume:11976) | `_launchTraktPercentSpent` → `true` | killed: C68 |
| `ref-22` (_maybeRestoreResume:11977) | `_launchTraktPercentSpent = true;` → `` | killed: C07, C08, C09, C68 |
| `ref-23` (_maybeRestoreResume:12004) | `_currentEpisodeTraktPercent();` → `Future<double?>.value(null);` | killed: C68 |
| `ref-24` (_maybeRestoreResume:12103) | `_currentEpisodeTraktPercent(forGuide: true);` → `Future<double?>.value(null);` | killed: C07 |
| `ref-25` (_tvScrubCommit:12786) | `_traktScrobbleSeek(target);` → `` | killed: C65 |
| `ref-26` (_buildTvControls:12855) | `_traktScrobbleSeek(target);` → `` | killed: C64 |
| `ref-27` (_handleDoubleTap:13343) | `_traktScrobbleSeek(clamped);` → `` | killed: C60, C62 |
| `ref-28` (_onPanEnd:13441) | `_traktScrobbleSeek(target);` → `` | killed: C63 |
| `ref-29` (build:14425) | `_traktScrobbleSeek(newPos);` → `` | killed: C59 |
| `ref-30` (build:14439) | `_traktScrobbleSeek(newPos);` → `` | killed: C61 |
| `ref-31` (build:14977) | `_traktScrobbleSeek(settledPosition);` → `` | killed: C43, C46, C55 |
| `ref-32` (_VpSkipSegmentHostAdapter:17497) | `_traktScrobbleSeek` → `_simklScrobbleSeek` | killed: C76, C77 |

**Early initializer audit.** Enabled stays false during held policy/auth:
early playing and user seek cannot send or arm a heartbeat. Launch budget
starts unspent and the first original resume caller consumes it once; later
episodes use their own stored percentage. Last action starts null, allowing
the first authenticated start. Heartbeat starts null and can be cancelled
during disabled/early disposal. All four are non-equivalent and have literal
or uninitialized-field assertion witnesses. The cache initializer null→empty
is equivalent: the shared identity begins null, every reader invokes the
binder before inspecting the cache, and its first different non-null identity
clears all three caches. A Simkl/MDBList reader binding first also clears it.
This is a caller-order proof, not reliance on initialization-waiting fixtures.

**Other equivalents / reachability.** Dart switch cases terminate implicitly,
so deleting the three explicit breaks cannot cause fallthrough. Only enabled
init/play/seek paths install the heartbeat, and enabled is assigned once with
no subsequent false write. A cancelled timer pointer is only cancelled again
or overwritten; retained nulling cannot change a later callback. SeriesPlaylist
is derived from a non-null active playlist; row indices come from valid entry
indices, so an invalid current index also returns null through the later
missing-row guard. Temporary playlist replacement invalidates/rebuilds its
series cache before readers inspect it. Non-negative original indices are
immutable and unique (generated absent guide rows use -1), so scanning after
the first match cannot choose another valid current row. These candidates
have completed surviving original replays; `equivalence-audit.json` records
the original construction/assignment anchors and invariant reasons.
Removing coordinate rejection is **not** equivalent: public snapshot storage
accepts a malformed `null_null` key, now pinned through single-file resume.

**Preserved asynchronous behavior / Follow-ups.** Late auth samples the live
playing/duration/position state; >80 sends stop without a heartbeat. Init has
no catch: cipher/storage errors escape, and a profile switch during cipher
authorization emits the original ResourceAuthorizationException. A profile
switch before the pending policy read resolves can use incoming credentials
for the still-mounted outgoing route. No profile fix is included.
Snapshot readers capture show identity before storage but read episode/index
after it: same-show changes use the current episode, different-show results
are rejected by the shared binder, A→B→A accepts old A over newer A, and a
concurrent Simkl read resets the shared caches. Original ready playlist callers
can attempt an outgoing resume seek after profile change/disposal; these gaps
are explicitly retained, not fixed. The profile snapshot case holds the
independent browser refresh HTTP request so its upstream error does not mask
the percentage-reader assertion. Exploratory upstream service errors remain
archived and uncredited. Ordinary protocol/seek cases explicitly assert no
uncaught or framework error and drain disposal timers.

**Device-pending / subsequent work.** PiP seek occurrence `ref-18` is installed
behind sealed Android/iOS platform predicates; no new platform seam. End-of-series
manual Trakt movie/series start, pause, seek, stop, >80 watched and cross-device
resume remain pending. There are no dormant moved Trakt methods. Step 1 will
register the ten new Trakt test files, enable P5 current/analyzer CI, and
implement the validated source-guard retarget. Phase 6 will move Simkl/MDBList.

**Evidence routing deviation.** One exploratory retry omitted the explicit
evidence-root override and created nine fixture directories in the old P2
default. All nine were relocated into `p5/step0/retry-evidence-correction/`;
`retry-evidence-correction.json` records the exact paths. That run is uncredited.
Accepted controls/mutations/baseline explicitly set the P5 root. No production
move, application change, new seam, dependency change, allowlisting, device
command, push, merge or branch switch.

## Phase 5 Step 0b — independent sample and transient-duration closure (2026-10-12)

Claude sampled original `1347a5ad8`: **17/18 valid killed (94%)**.
Evidence: `p5/claude-sample/p5-claude-muts.json`, per-mutation logs and
`results.json`. The one survivor feeds Trakt through the retained State-owned
`_persistablePosition`; it is a real coverage gap, now closed without an
application change.

| Independent mutation | Original sample result | Assertion case(s) / closure |
|---|---|---|
| `h1` | killed | Trakt initialization type gate prevents play seek heartbeat and dispose sends |
| `h2` | killed | Trakt initialization target gate prevents play seek heartbeat and dispose sends; Trakt initialization custom gate prevents play seek heartbeat and dispose sends |
| `h3` | killed | Trakt held auth initialization paused completion samples live state |
| `h4` | killed | Trakt unresolved episode creates no latent seek or start heartbeat when coordinates arrive later; Trakt held auth completion above eighty sends stop without arming heartbeat |
| `h5` | killed | Trakt progress samples held unlanded resume rather than the raw restart position |
| `h6` | killed | Trakt pause transition at 80 percent keeps strict watched threshold; Trakt playing transition at 80 percent keeps strict watched threshold; Trakt heartbeat interval replaces previous timer bypasses dedup then stops above eighty |
| `h7` | killed | Trakt progress beyond duration or position uses original clamped percent; Trakt pause transition at 81 percent keeps strict watched threshold |
| `h8` | killed | Trakt seek rearms heartbeat and restores start dedup after a watched stop; Trakt protocol episode start pause stop bodies and duplicate edges; Trakt protocol movie start pause stop bodies and duplicate edges; Trakt TV scrub confirm sends progress while the native pause is still suspended |
| `h9` | killed | skip tracker seek order arms Trakt heartbeat before Simkl; Trakt seek rearms heartbeat and restores start dedup after a watched stop; Trakt heartbeat live gates paused retain the original timer without sending or logging a checkpoint; Trakt heartbeat live gates duration retain the original timer without sending or logging a checkpoint |
| `h10` | killed | Trakt heartbeat live gates paused retain the original timer without sending or logging a checkpoint |
| `h11` | killed | Trakt heartbeat interval replaces previous timer bypasses dedup then stops above eighty |
| `h12` | killed | Trakt heartbeat restores start dedup after an implicit stop with a live timer |
| `h13` | killed | Trakt validation-active key releases held resume target before its early return |
| `h14` | killed | Trakt disabled key releases held resume target before its early return; Trakt validation-active key releases held resume target before its early return |
| `h15` | killed | Trakt seek target before landing is sent immediately without sampling the old position; Trakt keyboard rewind seek sends the clamped target; Trakt double tap left seek reaches the original tracking caller; Trakt keyboard forward seek sends the clamped target |
| `h16` | killed | skip tracker seek order arms Trakt heartbeat before Simkl; Trakt seek rearms heartbeat and restores start dedup after a watched stop |
| `h17` | survived | C78/C79 now assertion-kill h17 on original application |
| `h18` | killed | Trakt progress samples held unlanded resume rather than the raw restart position; Trakt protocol episode start pause stop bodies and duplicate edges; Trakt protocol movie start pause stop bodies and duplicate edges; Trakt pause transition at 80 percent keeps strict watched threshold |

| Addendum case / retained dependency | Original behavior / assertion-failing witness |
|---|---|
| C78 — `_persistablePosition`, 750,000 ms duration | Requested resume 600,000 ms was held at the original 1,200,000 ms duration; seek fails and raw position remains 80 ms. At exactly 80% of the new duration, pause, play and heartbeat all report `80 / 750000 * 100`, with no automatic stop. Both h17 removal and `>=`→`>` assertion-fail this case. |
| C79 — `_persistablePosition`, 600,000 ms duration | Held target becomes 100% of transient duration, but pause, play and heartbeat report `80 / 600000 * 100`; no watched/automatic-stop scrobble. h17 removal assertion-fails this case. |
| `h17` closure | Delete held-target >=80% fallback: two assertion kills; original detached HEAD `1347a5ad8`, application source identical to `315028407`; restored after each run. |
| `boundary-equality` | Change held-target >= to >: one assertion kill, exact-80 case. |

The existing 191-point moved-declaration/retained-reference matrix remains
180 killed / ten equivalent / one PiP device-pending. These two supplemental
mutations cover a State-owned dependency and do not change those fates.
New Trakt cases total 77 (plus two existing skip integration controls).
The independent sample remains reported as 17/18; the separate h17 replay
documents the closed survivor. Commands, control, assertion text, patches,
test hashes and restoration: `p5/step0b/mutation-results.json`.

Changed test format/analyzer pass. The new full-suite baseline runs on the
clean addendum commit before any production move and compares by identity
against Step 0, requiring exactly two passing additions and unchanged original
outcomes. Baseline metadata/delta are in `p5/step0b/`. No bug fix, production
move, seam, real network, dependency change or allowlisting.

## Phase 5 Step 1 — frozen Trakt production creation (2026-10-12)

Creation follows addendum `e0772d8d8`; application original `315028407`.
The clean addendum baseline has 13,049 successes, unchanged 13 failures /
28 load errors / 20 skips: exactly C78/C79 added, all previous outcomes identical
(`p5/step0b/baseline*`, `suite-delta.json`). Commands/source hashes in
`p5/step1/completion.json` and `materialization-application.json`.

| Contract / check | Applied result |
|---|---|
| Ownership | Twelve Trakt declarations, `VpTraktScrobbler`, its frozen 21-member Host/adapter; eager State constructor appends `_trakt` after `_display`; current P5 checker zero differences |
| Retained references | All 32 counted occurrences preserve statement order. Simkl's two progress calls forward to `_trakt.traktProgress()`. The entire skip adapter is P5 `patched` with one counted receiver rewrite, not an earlier-destination patch |
| Shared lifecycle | Persistable-position code, season/episode resolution, both seek guard objects, shared identity and analytics timer stay State-owned; each dispose statement stays in its original position |
| Byte/token proof | Both application paths equal Step-T formatted materialization exactly; archived optional-comma, idempotence, construction and diagnostic proof reused; all 13 earlier destinations protected |
| Characterization / guards | 279 affected successes, no failure/skip: all video-player tests, auto-next routing, Android TV MDBList source guard and theme guards; new transient-duration cases pass on moved code |
| Source retarget | Old binder→external-audio slice replaced by validated LIVE `_currentEpisodeTraktPercent`, `_currentEpisodeSimklPercent`, `_currentEpisodeMdblistPercent` declarations. Every body must capture the live show and reject mismatched binder identity; complete current-facade validation pins the computed Trakt adapter. Carried TVMaze identity, metadata readiness and rewatch assertions retained |
| CI | P5 current/self/analyzer inventory; P1–P4 historical merges 31a347ad2/fc24e32ae/890df14d8/315028407; fetch-depth 0 and harness flag preserved; ten Trakt files registered; feature-wide format/analyze lists cover the new destination, retargeted root test added to format |
| Themes / architecture | Manifest, rendered set and all three frozen source-guard lists extended; existing exact bridge, facade back-import prohibition, pure boundaries and 500-line cap apply; architecture and negatives pass |
| Size | Facade 17,592→17,394, shrink-only dated baseline; controller/Host file 294 lines |
| Analyzer | Root/CI scoped 84 with zero additions beyond frozen P5 probe maxima; P1–P4 mappings preserved. Exact retained Trakt import produces the probe's recorded unused-import warning; allowlist adds only that mechanical warning. Destination import-order info is likewise frozen |

The first broad-root before/after check observed 51 removed diagnostics from
unchanged test/vendor files and generated build paths; no outside additions.
Every affected tracked source hash is unchanged. This analyzer scan variation
is recorded in `step1/analyzer-delta.json`, without changing the scoped
identity comparator, inventory maxima or production code. Initial strict
outside-equality attempt remains archived in `checks-initial.json`.

Clean-tree gate follows this creation commit: exact Step-0b suite identities,
all Dart/Kotlin self-tests/current/history checks, root/CI analyzer comparators,
format/size/architecture and both release builds. Additional source-guard
negative witnesses validate wrong live reader/adapter rejection on a detached
creation worktree. No bug fix, new seam or tracker redesign. Simkl/MDBList
extraction stays Phase 6; original profile/race gaps and human Trakt/PiP
checklist remain pending.

## Phase 5 gate fixture scheduling closure (2026-10-12)

First clean creation gate exposed one original load-sensitive profile snapshot
observation: expected a 480 s resume seek, but the fixed drain ended before
its public selection action completed. The identical assertion reproduced
on original `1347a5ad8` (one failure, two passes in isolation); moved creation
`edd4d9ca5` passed three isolation repeats. No production-body difference.

The test now retains and awaits `SeriesBrowser.onEpisodeSelected` after the
real storage barrier releases, for the five races and missing-row case. Every
value, count, identity rejection, absence and error assertion stays. The entire
eight-case file passes three times on original and moved code (24 + 24);
six original mutation runs still assertion-kill `snapshot-index`,
`snapshot-ep-null`, `snapshot-add-mounted`, `snapshot-add-generation`,
`snapshot-early-index`, `snapshot-guard`. Original application restored.

Evidence/NOTE: `p5/gate/profile-repeat/`, `profile-stabilization/` (commands,
hashes, assertion logs, patches). First raw gate retained as `first-suite.*`.
The recorded Step-0b expected identities remain unchanged; focused original
replays revalidate the only modified fixture file. No failure allowlisting,
no outcome acceptance and no application fix. The full clean-tree gate is
rerun after this test/docs-only commit. Previously completed app/tool checks
have identical inputs; their creation evidence is retained.

## Phase 5 clean-tree gate (2026-10-12)

Clean tested `09c43cb56`, production creation `edd4d9ca5`, baseline `e0772d8d8`;
application original `315028407`. Evidence `p5/gate/completion.json` records
all commands, sources, SDK/configuration, actual result identities and artifacts.

| Gate | Result |
|---|---|
| Full suite | 13,049 success / 13 pre-existing failure / 28 pre-existing load error / 20 skip; **exact** Step-0b identities and outcomes, zero added/missing/changed; official suite comparator PASS |
| Move/history/self-tests | 34 commands pass: all 26 existing Dart manifest self-tests, P5 universal real configurations/negatives, current and same-revision --at, P1–P4 --at merge revisions and complete Kotlin self-test |
| Analyzer | Root/CI comparator: 84 scoped occurrences, zero beyond frozen P5 maxima; infos and multiplicities included, earlier mappings preserved; CI allowlist 47 recorded warnings, nothing new/stale |
| Format / sizes / architecture | Exact CI format list, 2,998-file size check / 140 ratchets, architecture and negatives PASS; facade 17,394 / controller 294 |
| Source guard | Detached creation control passes; changing moved reader to widget identity or computed adapter to widget identity assertion-fails the retargeted Android TV test; sources restored |
| Release builds | Sequential nice-19 `flutter build apk --release --no-pub` and `flutter build macos --release --no-pub` PASS on clean creation; no install/run; APK/AOT hashes and build logs archived |
| Constraints | Exact two frozen application paths, all 13 earlier destinations protected, pubspec unchanged, all commit trailers checked, isolated parser flags/copy-kernel deletion audit PASS, every original mutation restored |

First gate failed one original timing flake; the identical assertion reproduced
on original (1/3), moved isolation passed 3/3. Awaiting the real public selection
Future preserves all assertions; original/moved full-file 3× controls and six
original mutation witnesses pass. No failure allowlist. First run is archived
as `first-suite.*`; this gate rerun has exact baseline outcomes.

The broad-root diagnostic scan variation noted in Step 1 remains recorded:
no outside additions in the accepted before/after scan, removals at unchanged
files/generated paths. A later broad scan emitted each of 84 physical player
diagnostics twice; that rejected attempt is archived. The canonical two-path
root-config command used at Step T emits 84 once each and passes the unchanged
comparator, as does CI. No deduplication or inventory expansion. No diagnostic allowance beyond the frozen P5 probe, and no test-failure allowlisting.
Known failures/load errors are observed baseline identities, not count-only
allowance. The independent sample stays 17/18 as observed, with h17 closed by
separate original assertion witnesses C78/C79. All 77 new Trakt cases pass on
moved code. Current ownership CI points to P5; Simkl/MDBList stay State-owned
except the two declared shared-percent forwardings, pending Phase 6.

Human end-of-series Trakt movie/episode start/pause/seek/stop, >80 watched,
cross-device resume and disabled-seek handover checks remain pending, including
sealed-platform PiP seek `ref-18`. Existing profile, A→B→A and post-disposal
reader gaps stay in Follow-ups. No bug fix, new seam, real API network,
allowlisting of failures, device command, push, merge or branch switch.
Stop after this gate.

## Phase 6 Step T — Simkl/MDBList tooling (2026-10-12)

Original `ea7901ead`, approved design `1c8ce8e7f`; 846 original spans:
24 moved / 820 retained / two patched. Complete draft `vplayer_p6.json`
compares both raw and formatted evidence-only materializations with zero
changes beyond counted edits. All 59 references are measured (57 retained,
two in the whole patched skip adapter). P5's Trakt forwarding stays in that
adapter; the P6 class projection carries two exact new rewrites. The State
constructor eagerly appends Simkl then MDBList after Trakt.

The eight field initializers are false literals or implicit null; no allocation,
Host read, service call or scheduling moves into construction. Both Hosts
(19 Simkl, 15 MDBList) and live widget selectors are frozen. The two complete
`_trakt.traktProgress` chains project to `_host.traktProgress` only through
explicit registrations. Guard-only missing registration, wrong leaf and
`_host`/`_trakt`/`widget` capture negatives pass; existing manifests retain their
behavior without a shared-guard implementation change. All 14 historical
feature destinations stay protected.

All 33 accepted tooling commands pass: all 26 existing Dart manifest self-tests,
P6 universal negatives and all-retained original comparison, P1–P5 same-revision
historical inputs, and complete Kotlin historical/compiled self-test. Root/
strict/raw/formatted inventories record 84/153/94/94 occurrences, preserving
all prior mappings/maxima and unchanged async-context identities. Five retained
facade import warnings and five destination directive infos are probe effects;
no suppression/import cleanup. Formatting inserts two AST-optional commas,
deletes none, is idempotent and introduces zero diagnostic changes. Sizes and
architecture pass. Parser flags and copy/kernel deletion are audited.

Fresh original full-suite evidence at the named merge is clean and has exact
P5 gate identities: 13,049 success / 13 failure / 28 load error / 20 skip. No new
outcome or failure allowlist. Evidence: `p6/tooling/` and `p6/step0/base*`.
Rejected development attempts remain archived: nonexistent disposal-negative
pattern (fixed and complete self-test rerun), and wrong P4 revision in a copied
driver (correct `--at 315028407` passes). Draft only; CI/source guard/theme/size
transition belongs to the commit creating both production scrobblers. No app,
pubspec, bug fix, real API network, push/merge/switch or device command.

## Phase 6 Step 0 — original Simkl/MDBList characterization (2026-10-12)

Application original `ea7901ead`; tooling `80a47fa2b`. The detached worktree
under `p6/step0/original/` contains that application throughout controls and
mutation proofs. The main worktree's application, pubspec, CI registrations,
theme/source-guard lists and file-size baseline remain unchanged. The complete
P6 manifest stays draft; both production destinations are absent.

The phase-5 isolate-wide delegating HTTP transport is reused. Both production
singleton clients keep their first client; each fixture redirects that client
to its own synthetic recorder. Credentials are seeded through real profile
storage, with the existing cipher barrier and mirrored ProfilePolicyGuard.
There is no real transport fallback. New barriers suspend actual immutable
policy/capability/storage completions at their public callers; they neither
forge results nor access private State. Public selections await `finish()`.

Protocols pin Simkl's local start marker, pause heartbeats, strict `>80` caller
threshold, failed-send dedup and transition-only seek. MDBList pins pause play/
sub-threshold exit, inclusive completion, raw initialization versus held resume,
target handoff, two-minute timers and response/revision ownership. Timer creation,
first active cancellation and callback ownership establish the Trakt → Simkl →
MDBList fan-out order without assuming asynchronous HTTP completion order.

The early-window matrix covers all eight moved initializers: false enablement/
launch budgets and null action/timer/session before delayed initialization; the
two null cache initializers are invariant-equivalent because every non-null
identity first runs the shared binder. Initialization also covers paused/zero
duration, active validation, disposal, incoming profile credentials, captured
MDBList target/capability, suspended player setup, propagated storage errors and
the separately caught player-initialization failure. Native progress may arrive
before seek acknowledgement; one fake opt-in suppresses its duplicate position
edge after acknowledgement, retaining the original default for every other test.

All 24 moved declarations and all 59 retained references are re-measured by name
at the original. The analyzer AST sweep enumerates 411 statement/branch/literal
sites, each mapped to concrete original mutations. There are 319 responsibility
points plus one retained initialization-caller witness: **301 assertion kills,
15 evidenced equivalences, two dormant defensive start branches and two sealed-
platform PiP references pending devices**. Every one of 142 new behavior cases
has an assertion-failing original witness with its final case-file hash. Existing
executable skip callers independently exercise both patched adapter forwarders.

Equivalence proofs include implicit switch termination, the immutable true
MDBList feature flag, the Simkl timer's enabled-only armers/idempotent inactive
cancellation, the nullable identity cache reset, bounded complete-pair parsing,
unique production row indices, overwritten local coordinate initializers and
the synchronous outer gate already protecting the sole MDBList pause caller.
The first broad sweep and all survivors remain archived; equivalence is never
inferred from a survivor. Compilation/load failures and error-only failures
never count as assertion kills.

Original continuations remain unchanged and are recorded in Follow-ups: target
disablement does not retire existing tracker state; Simkl's held response/25-second
409 recovery can outlive a route; capabilities distinguish MDBList disposal from
profile retirement; A→B→A can accept an older snapshot; callers can resume after
profile handoff/disposal; a source-validation gate can preserve an outgoing
MDBList target or playing bit. Failed ordinary opens retain the incoming tracker
target. Failed source preparation can checkpoint an unplayed target before both
rollback calls restore the outgoing session. A masked guide read can warm a cache
used by a later selected-provider resume. These are characterization, not fixes.

The source guard retarget stays deferred to Step 1: the validating reader's
Simkl/MDBList prefixes become `_host.`, preserving captured series identity,
stale-result rejection, TVMaze carry-forward and rewatch assertions. Independent
failing mutations of each new computed adapter are required then. No source-text
test is credited as behavior coverage here.

Development attempts are preserved: three first-sweep call deletions left a
dangling `await` and were replaced by flow-valid no-op futures; four expectation/
observation errors were corrected without changing production; the completed
empty-URL fast path did not expose the requested await barrier, so the transient
index case instead holds a real synthetic TorBox transport response. Explicit
normal-completion/diagnostic assertions replace error-only mutation evidence.
The final 144-case original control (142 additions plus two existing skip cases)
passes. The selected Trakt guide case's outer policy excludes local progress
before guide fallback; dedicated overlap cases pin both companion guide masks.

Evidence: `p6/step0/coverage.json`, `points.json`, `ast-site-matrix.json`,
`mutation-results.json`, `equivalence-proofs.json`, command logs and patches.
Full-suite additions-only comparison and final check results are recorded below.

### New behavior cases

| New characterization file (`test/features/video_player/`) | Cases |
|---|---|
| `video_player_mdblist_startup_test.dart` | 6 |
| `video_player_secondary_boundary_test.dart` | 20 |
| `video_player_secondary_early_policy_test.dart` | 2 |
| `video_player_secondary_fanout_test.dart` | 4 |
| `video_player_secondary_gate_release_test.dart` | 2 |
| `video_player_secondary_guide_mask_test.dart` | 4 |
| `video_player_secondary_guide_overlap_test.dart` | 2 |
| `video_player_secondary_index_race_test.dart` | 1 |
| `video_player_secondary_initialization_test.dart` | 21 |
| `video_player_secondary_lifecycle_test.dart` | 3 |
| `video_player_secondary_mdblist_validation_test.dart` | 5 |
| `video_player_secondary_pending_test.dart` | 8 |
| `video_player_secondary_protocol_test.dart` | 11 |
| `video_player_secondary_reader_boundaries_test.dart` | 11 |
| `video_player_secondary_seek_inputs_test.dart` | 7 |
| `video_player_secondary_simkl_policy_test.dart` | 2 |
| `video_player_secondary_snapshots_test.dart` | 16 |
| `video_player_secondary_source_pending_test.dart` | 1 |
| `video_player_secondary_suspended_transition_test.dart` | 3 |
| `video_player_secondary_switch_rollback_test.dart` | 4 |
| `video_player_secondary_timing_test.dart` | 9 |

### Step-0 baseline and checks

The clean named original was re-run before additions. The final staged test tree
`746453f37ec5e5d7c58c9dd7d63ed031ea35484d` has **13,191 success / 13 failure /
28 load error / 20 skip**. `suite_evidence.py compare` and a strict comparison
of every old identity/outcome both pass: exactly **142 added passing identities**,
zero changed/missing/newly skipped/fixed old identities. No failure allowlist or
`test_baseline.py --record`. Flutter 3.44.8 (`058e0af2c2b57e369d905a03ac9748b0ebf543c6`),
Dart 3.12.2, same SDK/configuration as the fresh original. The suite's nonzero
exit is the observed original failures/load errors; it is not a new-test failure.
`final-suite.env.json` records no tree change during the run. Subsequent changes
are documentation/evidence only; application and tested test blobs remain exact.

| Check / command | Recorded result |
|---|---|
| Original controls and mutations: `nice -n 19 flutter test <selected files> --concurrency=1 --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true --reporter=json` | Final 144-case control passes; 301 points have assertion failures at final case-file inputs; all 15 equivalence candidates have passing final-input original replays and separate source proofs |
| Full suite: `nice -n 19 python3 dev/tool/suite_evidence.py run vplayer/p6/step0/final-suite --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true`; `suite_evidence.py compare --against <p6>/step0/base.jsonl <p6>/step0/final-suite.jsonl` | Exact old identities/outcomes; 142 passing additions only |
| `nice -n 19 dart analyze <25 changed/new test files>` | No issues; unchanged application diagnostics reuse Step T's root/strict probe |
| `nice -n 19 dart format --output=none --set-exit-if-changed <25 changed/new test files>` | 25 files, zero changes |
| `check_file_sizes.py`; `check_search_architecture.py` | 2,998 files / 140 ratchets; 1,666 migrated files pass; baselines unchanged |
| Step T manifest/history/analyzer evidence reused | All 33 accepted commands still apply: no application, checker, manifest or configuration change since `80a47fa2b`; includes all Dart manifest self-tests, Kotlin self-test and P1–P5 `--at` |
| Parser routing and restoration audit | Every manifest CLI has an explicit isolated parser package; nested source parses use fresh `.dart_tool/vplayer_parser/` copies with copied `*.dill` removed; all mutations restored to the original |

Evidence is only under `<git-common-dir>/refactor-evidence/vplayer/p6/`.
The evidence-only runner writes its real commands, selected names, completed
assertion messages, patches and test SHA-256 inputs to `mutation-results.json`.
The opt-in fake seek acknowledgement switch retains its old default; the original
control and full-suite identity comparison cover that unchanged default. Early
attempts using other test-support hashes remain archived rather than overwritten.
One equivalence replay predated the final reader-boundary file; its final-input
29-case replay passes and is recorded separately as `audit-snapshot-simkl-bounds`.

The matrices below cover 24 moved declarations and all 59 retained occurrences;
`ast-site-matrix.json` maps every one of the 411 individual AST sites to a concrete
point. The final case table maps every addition to an assertion witness. The
mutation table includes the extra `caller-init-mounted` proof; abbreviated token
fragments are backed by complete spans/patches in `points.json` and `mutations/`.
Two dormant Simkl start branches and two PiP device references receive no executable
coverage credit. Both production scrobblers, CI transition, source-guard adapter
retarget proofs and manual Simkl/MDBList/PiP device checklist remain future steps.
Stop after Step 0; no production move or bug fix.

### Declaration and retained-reference coverage

| Moved declaration (original name) | AST statement / branch / literal sites | Concrete mutation points and results |
|---|---|---|
| `_simklScrobbleEnabled` | 1 | killed: 1; `field-simklScrobbleEnabled` |
| `_launchSimklPercentSpent` | 1 | killed: 1; `field-launchSimklPercentSpent` |
| `_simklEpisodeProgress` | 1 | equivalent: 1; `field-simklEpisodeProgress` |
| `_mdblistEpisodeProgress` | 1 | equivalent: 1; `field-mdblistEpisodeProgress` |
| `_launchMdblistPercentSpent` | 1 | killed: 1; `field-launchMdblistPercentSpent` |
| `_simklLastScrobbleAction` | 1 | killed: 1; `field-action` |
| `_simklHeartbeatTimer` | 1 | killed: 1; `field-timer` |
| `_mdblistSession` | 1 | killed: 1; `field-session` |
| `_initSimklScrobble` | 26 | killed: 14; equivalent: 1; `simkl-init-flag`, `simkl-init-id`, `simkl-init-type`, `simkl-init-movie`, `simkl-init-series`, `simkl-init-policy-content`, `simkl-init-policy`, `simkl-init-auth`, `simkl-init-mounted`, `simkl-init-validation`, `simkl-init-enabled`, `simkl-init-playing`, `simkl-init-duration`, `simkl-init-marker`, `simkl-init-heartbeat` |
| `_simklSeriesSEUnresolved` | 8 | killed: 3; equivalent: 1; `simkl-unresolved-series`, `simkl-unresolved-season`, `simkl-unresolved-episode`, `simkl-unresolved-or` |
| `_simklScrobble` | 38 | killed: 26; equivalent: 2; dormant: 2; `simkl-send-api-0-call`, `simkl-send-api-0-id`, `simkl-send-api-0-progress`, `simkl-send-api-0-season`, `simkl-send-api-0-episode`, `simkl-send-api-1-call`, `simkl-send-api-1-id`, `simkl-send-api-1-progress`, `simkl-send-api-1-season`, `simkl-send-api-1-episode`, `simkl-send-break-0`, `simkl-send-break-1`, `simkl-send-validation`, `simkl-send-enabled`, `simkl-send-id`, `simkl-send-capture`, `simkl-send-percent`, `simkl-send-se`, `simkl-send-unresolved`, `simkl-send-threshold`, `simkl-send-upper`, `simkl-send-pause`, `simkl-send-stop`, `simkl-send-dedup`, `simkl-send-marker`, `simkl-send-start-intent`, `simkl-send-start-case`, `ast-048`, `ast-073`, `ast-077` |
| `_startSimklHeartbeat` | 40 | killed: 34; equivalent: 1; `simkl-beat-api-0-call`, `simkl-beat-api-0-id`, `simkl-beat-api-0-progress`, `simkl-beat-api-0-season`, `simkl-beat-api-0-episode`, `simkl-beat-api-1-call`, `simkl-beat-api-1-id`, `simkl-beat-api-1-progress`, `simkl-beat-api-1-season`, `simkl-beat-api-1-episode`, `simkl-beat-cancel`, `simkl-beat-interval`, `simkl-beat-validation`, `simkl-beat-id`, `simkl-beat-playing`, `simkl-beat-duration`, `simkl-beat-capture`, `simkl-beat-percent`, `simkl-beat-se`, `simkl-beat-unresolved`, `simkl-beat-threshold`, `simkl-beat-upper`, `simkl-beat-stop-marker`, `simkl-beat-stop-heartbeat`, `simkl-beat-pause-marker`, `simkl-beat-precision`, `simkl-beat-stop-log`, `simkl-beat-pause-log`, `simkl-beat-enabled`, `ast-088`, `ast-093`, `ast-109`, `ast-111`, `ast-118`, `ast-119` |
| `_stopSimklHeartbeat` | 3 | killed: 1; equivalent: 1; `simkl-stop-cancel`, `simkl-stop-null` |
| `_simklScrobbleSeek` | 40 | killed: 33; `simkl-seek-api-0-call`, `simkl-seek-api-0-id`, `simkl-seek-api-0-progress`, `simkl-seek-api-0-season`, `simkl-seek-api-0-episode`, `simkl-seek-api-1-call`, `simkl-seek-api-1-id`, `simkl-seek-api-1-progress`, `simkl-seek-api-1-season`, `simkl-seek-api-1-episode`, `simkl-seek-validation`, `simkl-seek-enabled`, `simkl-seek-id`, `simkl-seek-playing`, `simkl-seek-duration`, `simkl-seek-capture`, `simkl-seek-position`, `simkl-seek-scale`, `simkl-seek-low`, `simkl-seek-high`, `simkl-seek-se`, `simkl-seek-unresolved`, `simkl-seek-threshold`, `simkl-seek-upper`, `simkl-seek-stop-dedup`, `simkl-seek-stop-marker`, `simkl-seek-stop-heartbeat`, `simkl-seek-reverse-threshold`, `simkl-seek-reverse-stop`, `simkl-seek-reverse-marker`, `simkl-seek-reverse-heartbeat`, `ast-129`, `ast-134` |
| `_mdblistTarget` | 27 | killed: 11; `md-target-capture`, `md-target-null`, `md-target-empty`, `md-target-ids`, `md-target-movie`, `md-target-series`, `md-target-se`, `md-target-unresolved`, `md-target-season`, `md-target-episode`, `ast-174` |
| `_initMdblistScrobble` | 64 | killed: 39; equivalent: 1; `md-init-flag`, `md-init-policy-content`, `md-init-policy`, `md-init-player-wait`, `md-init-target`, `md-init-null-target`, `md-init-capability`, `md-init-late-target`, `md-init-session-capability`, `md-init-raw-position`, `md-init-zero-position`, `md-init-zero-duration`, `md-init-assignment`, `md-init-validation`, `md-init-playing`, `md-init-duration`, `md-init-play`, `md-init-mounted-0`, `md-init-mounted-1`, `md-init-player-catch`, `md-init-feature-flag`, `log-initMdblistScrobble-0`, `log-initMdblistScrobble-1`, `log-initMdblistScrobble-2`, `log-initMdblistScrobble-3`, `log-initMdblistScrobble-4`, `log-initMdblistScrobble-5`, `ast-193`, `ast-194`, `ast-195`, `ast-199`, `ast-206`, `ast-218`, `ast-225`, `ast-230`, `ast-237`, `ast-238`, `ast-239`, `ast-243`, `ast-246` |
| `_updateMdblistPosition` | 3 | killed: 4; `md-updateMdblistPosition-validation`, `md-position-position`, `md-position-duration`, `md-position-update` |
| `_mdblistPlay` | 4 | killed: 3; `md-mdblistPlay-validation`, `md-mdblistPlay-update`, `md-call-mdblistPlay-play` |
| `_mdblistPause` | 4 | equivalent: 1; killed: 2; `md-mdblistPause-validation`, `md-mdblistPause-update`, `md-call-mdblistPause-pause` |
| `_mdblistStop` | 23 | killed: 12; `md-mdblistStop-validation`, `md-mdblistStop-update`, `md-call-mdblistStop-complete`, `md-call-mdblistStop-exit`, `md-stop-complete`, `md-stop-default`, `log-mdblistStop-0`, `ast-272`, `ast-273`, `ast-274`, `ast-279`, `ast-282` |
| `_mdblistScrobbleSeek` | 3 | killed: 4; `md-mdblistScrobbleSeek-validation`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration` |
| `_switchMdblistTarget` | 9 | killed: 7; `md-switchMdblistTarget-validation`, `md-switch-target`, `md-switch-null`, `md-switch-exit`, `md-switch-call`, `md-switch-await`, `ast-298` |
| `_currentEpisodeSimklPercent` | 73 | killed: 27; equivalent: 5; `snapshot-simkl-default`, `snapshot-simkl-policy-content`, `snapshot-simkl-policy-mask`, `snapshot-simkl-guide-bypass`, `snapshot-simkl-identity`, `snapshot-simkl-null-id`, `snapshot-simkl-bind`, `snapshot-simkl-cache`, `snapshot-simkl-guard`, `snapshot-simkl-late-guard`, `snapshot-simkl-assign`, `snapshot-simkl-guide-mask`, `snapshot-simkl-branch`, `snapshot-simkl-series`, `snapshot-simkl-empty`, `snapshot-simkl-index`, `snapshot-simkl-season`, `snapshot-simkl-episode`, `snapshot-simkl-fallback`, `snapshot-simkl-fallback-season`, `snapshot-simkl-fallback-episode`, `snapshot-simkl-unresolved`, `snapshot-simkl-key`, `snapshot-simkl-bounds`, `snapshot-simkl-negative`, `snapshot-simkl-break`, `ast-316`, `ast-322`, `ast-323`, `ast-324`, `ast-329`, `ast-333` |
| `_currentEpisodeMdblistPercent` | 38 | killed: 17; `snapshot-mdblist-default`, `snapshot-mdblist-policy-content`, `snapshot-mdblist-policy-mask`, `snapshot-mdblist-guide-bypass`, `snapshot-mdblist-identity`, `snapshot-mdblist-null-id`, `snapshot-mdblist-bind`, `snapshot-mdblist-cache`, `snapshot-mdblist-guard`, `snapshot-mdblist-late-guard`, `snapshot-mdblist-assign`, `snapshot-mdblist-guide-mask`, `snapshot-mdblist-branch`, `snapshot-mdblist-se`, `snapshot-mdblist-unresolved`, `snapshot-mdblist-key`, `ast-389` |

| Retained occurrence (original declaration:line) | Original reference / caller | Result / original assertion |
|---|---|---|
| `ref-01` (initState:1677) | `_initSimklScrobble();` | killed: C091 |
| `ref-02` (initState:1678) | `_initMdblistScrobble();` | killed: C061, C058 |
| `ref-03` (_resumeTrackingAfterValidationGate:2104) | `_simklScrobbleEnabled` | killed: C049, C048, C047, C050 |
| `ref-04` (_resumeTrackingAfterValidationGate:2107) | `_simklLastScrobbleAction = 'start';` | killed: C142 |
| `ref-05` (_resumeTrackingAfterValidationGate:2108) | `_startSimklHeartbeat();` | killed: C116 |
| `ref-06` (_resumeTrackingAfterValidationGate:2100) | `_updateMdblistPosition();` | killed: C028 |
| `ref-07` (_resumeTrackingAfterValidationGate:2110) | `_mdblistPlay();` | killed: C013 |
| `ref-08` (_bindEpisodeTrackerProgressIdentity:2130) | `_simklEpisodeProgress = null;` | killed: C109, C037 |
| `ref-09` (_bindEpisodeTrackerProgressIdentity:2131) | `_mdblistEpisodeProgress = null;` | killed: C077, C038 |
| `ref-10` (_bindPlayerInstanceSubscriptions:3413) | `_simklScrobbleEnabled` | killed: C095, C098, C093, C096, C099 |
| `ref-11` (_bindPlayerInstanceSubscriptions:3416) | `_simklLastScrobbleAction = 'start';` | killed: C044, C045, C043 |
| `ref-12` (_bindPlayerInstanceSubscriptions:3422) | `_simklLastScrobbleAction` | killed: C035, C036, C033, C034, C052, C085, C086, C087, C088 |
| `ref-13` (_bindPlayerInstanceSubscriptions:3423) | `_simklScrobble('pause');` | killed: C035, C036, C033, C034, C052, C085, C086, C087, C088 |
| `ref-14` (_bindPlayerInstanceSubscriptions:3417) | `_startSimklHeartbeat();` | killed: C035, C036, C033, C034, C087, C088, C114 |
| `ref-15` (_bindPlayerInstanceSubscriptions:3424) | `_stopSimklHeartbeat();` | killed: C035, C087, C088 |
| `ref-16` (_bindPlayerInstanceSubscriptions:3332) | `_updateMdblistPosition();` | killed: C035, C036, C033, C034, C087, C088 |
| `ref-17` (_bindPlayerInstanceSubscriptions:3371) | `_updateMdblistPosition();` | killed: C022 |
| `ref-18` (_bindPlayerInstanceSubscriptions:3377) | `_mdblistPlay();` | killed: C114 |
| `ref-19` (_bindPlayerInstanceSubscriptions:3427) | `_mdblistPlay();` | killed: C035, C036, C033, C034, C087, C088 |
| `ref-20` (_bindPlayerInstanceSubscriptions:3432) | `_mdblistPause();` | killed: C035, C036, C033, C034, C052, C085, C086, C087, C088 |
| `ref-21` (_onPlaybackEnded:4740) | `_simklScrobble('stop');` | killed: C033 |
| `ref-22` (_onPlaybackEnded:4739) | `_stopSimklHeartbeat();` | killed: C033 |
| `ref-23` (_onPlaybackEnded:4741) | `_mdblistStop(complete: true);` | killed: C033 |
| `ref-24` (_switchToSourcePlaylist:9071) | `_switchMdblistTarget();` | killed: C009 |
| `ref-25` (_loadPlaylistIndex:10041) | `_switchMdblistTarget();` | killed: C009 |
| `ref-26` (_loadPlaylistIndexAttempt:10145) | `_simklScrobble('stop');` | killed: C137 |
| `ref-27` (_loadPlaylistIndexAttempt:10144) | `_stopSimklHeartbeat();` | killed: C137 |
| `ref-28` (_loadPlaylistIndexAttempt:10149) | `_updateMdblistPosition();` | killed: C021 |
| `ref-29` (_loadPlaylistIndexAttempt:10164) | `_switchMdblistTarget();` | killed: C008 |
| `ref-30` (_onPipAction:11260) | `_simklScrobbleSeek(position);` | device_pending: Installed only behind sealed Android/iOS predicates; no raw Platform seam. Human PiP seek checklist. |
| `ref-31` (_onPipAction:11261) | `_mdblistScrobbleSeek(position);` | device_pending: Installed only behind sealed Android/iOS predicates; no raw Platform seam. Human PiP seek checklist. |
| `ref-32` (dispose:11455) | `_simklScrobble('stop');` | killed: C034, C085, C086 |
| `ref-33` (dispose:11454) | `_stopSimklHeartbeat();` | killed: C034, C046 |
| `ref-34` (dispose:11457) | `_mdblistSession?.close()` | killed: C046, C005 |
| `ref-35` (dispose:11456) | `_mdblistStop();` | killed: C016 |
| `ref-36` (_maybeRestoreResume:11728) | `_launchSimklPercentSpent` | killed: C101 |
| `ref-37` (_maybeRestoreResume:11729) | `_launchSimklPercentSpent = true;` | killed: C101 |
| `ref-38` (_maybeRestoreResume:11779) | `_currentEpisodeSimklPercent()` | killed: C101, C106 |
| `ref-39` (_maybeRestoreResume:11856) | `_currentEpisodeSimklPercent(forGuide: true)` | killed: C102 |
| `ref-40` (_maybeRestoreResume:11730) | `_launchMdblistPercentSpent` | killed: C071 |
| `ref-41` (_maybeRestoreResume:11731) | `_launchMdblistPercentSpent = true;` | killed: C071 |
| `ref-42` (_maybeRestoreResume:11764) | `_currentEpisodeMdblistPercent()` | killed: C071, C075 |
| `ref-43` (_maybeRestoreResume:11857) | `_currentEpisodeMdblistPercent(         forGuide: true,       )` | killed: C072 |
| `ref-44` (_tvScrubCommit:12539) | `_simklScrobbleSeek(target);` | killed: C032 |
| `ref-45` (_tvScrubCommit:12540) | `_mdblistScrobbleSeek(target);` | killed: C032 |
| `ref-46` (_buildTvControls:12608) | `_simklScrobbleSeek(target);` | killed: C031 |
| `ref-47` (_buildTvControls:12609) | `_mdblistScrobbleSeek(target);` | killed: C031 |
| `ref-48` (_handleDoubleTap:13096) | `_simklScrobbleSeek(clamped);` | killed: C040, C041 |
| `ref-49` (_handleDoubleTap:13097) | `_mdblistScrobbleSeek(clamped);` | killed: C040, C041 |
| `ref-50` (_onPanEnd:13194) | `_simklScrobbleSeek(target);` | killed: C053 |
| `ref-51` (_onPanEnd:13195) | `_mdblistScrobbleSeek(target);` | killed: C053 |
| `ref-52` (build:14178) | `_simklScrobbleSeek(newPos);` | killed: C055 |
| `ref-53` (build:14192) | `_simklScrobbleSeek(newPos);` | killed: C054 |
| `ref-54` (build:14730) | `_simklScrobbleSeek(settledPosition);` | killed: C088, C057, C055 |
| `ref-55` (build:14179) | `_mdblistScrobbleSeek(newPos);` | killed: C055 |
| `ref-56` (build:14193) | `_mdblistScrobbleSeek(newPos);` | killed: C054 |
| `ref-57` (build:14731) | `_mdblistScrobbleSeek(settledPosition);` | killed: C087, C088, C055 |
| `ref-58` (_VpSkipSegmentHostAdapter:17301) | `_simklScrobbleSeek` | killed: skip publishes clock before seek, queues tracking before haptic and preserves remote stop order, skip tracker seek order arms Trakt heartbeat before Simkl |
| `ref-59` (_VpSkipSegmentHostAdapter:17303) | `_mdblistScrobbleSeek` | killed: skip publishes clock before seek, queues tracking before haptic and preserves remote stop order, skip tracker seek order arms Trakt heartbeat before Simkl |

### Original assertion witnesses and mutation table

| Case | Original caller / observable assertion | Original assertion witness |
|---|---|---|
| C001 | MDBList capability finishing paused allocates without starting until the real playing edge | `final2-md-init-playing` |
| C002 | MDBList captured target before capability dispose completion retains original allocation and guards | `md-init-capability`, `md-init-mounted-1`, `log-initMdblistScrobble-4`, `ast-230` |
| C003 | MDBList captured target before capability profile completion retains original allocation and guards | `md-target-capture`, `md-target-ids`, `md-init-target`, `md-init-capability`, `md-init-session-capability`, `md-init-play`, `log-initMdblistScrobble-5`, `ast-237`, `ast-238`, `ast-239`, `ast-243`, `ast-246` |
| C004 | MDBList captured target before capability widget completion retains original allocation and guards | `md-target-capture`, `md-target-ids`, `md-target-se`, `md-target-season`, `md-target-episode`, `md-init-target`, `md-init-capability`, `md-init-late-target`, `md-init-zero-position`, `md-init-zero-duration`, `md-init-play`, `log-initMdblistScrobble-5`, `ast-237`, `ast-238`, `ast-239`, `ast-243`, `ast-246` |
| C005 | MDBList close awaits failed outgoing completion and retries its captured target before finishing disposal | `md-stop-default`, `ref-34` |
| C006 | MDBList disposal after successful player setup but before policy delivery returns before capability diagnostics | `final2-md-init-mounted-0` |
| C007 | MDBList episode selection with newly invalid live identity exits then continues its outgoing target | `final2-md-switch-null`, `final2-md-switch-exit`, `final2-ast-298` |
| C008 | MDBList failed ordinary incoming open retains the incoming tracker target as the original does | `final-ref-29` |
| C009 | MDBList failed source preparation checkpoints the unplayed target then restores the outgoing session | `final-ref-24`, `final-ref-25` |
| C010 | MDBList held resume dispose samples its promised position before any intervening native position event | `final-md-mdblistStop-update` |
| C011 | MDBList held resume play samples its promised position before any intervening native position event | `final-md-mdblistPlay-update` |
| C012 | MDBList late capability during manual validation keeps its original checkpoint at late-close | `final2-md-init-validation`, `final2-md-mdblistPlay-validation`, `final2-md-mdblistStop-validation` |
| C013 | MDBList late capability during manual validation keeps its original checkpoint at late-release | `final2-md-init-validation`, `final2-ref-07` |
| C014 | MDBList live seek and duration edge during manual validation keeps its original checkpoint at early-close | `final2-md-mdblistStop-validation`, `final2-md-mdblistScrobbleSeek-validation` |
| C015 | MDBList only catches player initialization failure and never allocates a session for the failed controller | `md-init-player-wait`, `md-init-player-catch`, `log-initMdblistScrobble-2` |
| C016 | MDBList ordinary disposal logs its session exit before close exactly once | `final-md-call-mdblistStop-exit`, `final-ref-35` |
| C017 | MDBList pending checkpoint across an explicit source playlist switch preserves validation gating and the existing target | `md-target-capture`, `md-target-ids`, `md-target-se`, `md-target-season`, `md-target-episode`, `md-switchMdblistTarget-validation` |
| C018 | MDBList pending outgoing checkpoint across dispose preserves payload owner revisions and timer cleanup | `md-target-capture`, `md-target-ids`, `md-target-se`, `md-target-season`, `md-target-episode` |
| C019 | MDBList pending outgoing checkpoint across episode preserves payload owner revisions and timer cleanup | `md-target-capture`, `md-target-ids`, `md-target-se`, `md-target-season`, `md-target-episode`, `md-switch-target`, `md-switch-call`, `md-switch-await` |
| C020 | MDBList pending outgoing checkpoint across profile preserves payload owner revisions and timer cleanup | `md-target-capture`, `md-target-ids`, `md-target-se`, `md-target-season`, `md-target-episode` |
| C021 | MDBList playlist switch captures an unlanded outgoing resume before clearing its guard | `final-ref-28` |
| C022 | MDBList positive duration replacement updates the heartbeat denominator without another position or playing event | `final-ref-17` |
| C023 | MDBList startup disabled preserves exact requested and rejection diagnostics | `final-log-initMdblistScrobble-0`, `final-log-initMdblistScrobble-1`, `final-ast-193`, `final-ast-194`, `final-ast-195`, `final-ast-199` |
| C024 | MDBList startup empty preserves exact requested and rejection diagnostics | `final-md-target-empty`, `final-log-initMdblistScrobble-3` |
| C025 | MDBList startup policy precedes suspended player setup and dispose preserves the captured setting | `field-session`, `md-init-player-wait`, `ast-218` |
| C026 | MDBList startup policy precedes suspended player setup and none preserves the captured setting | `field-session`, `md-init-player-wait`, `md-init-target`, `md-init-zero-position`, `md-init-zero-duration`, `md-init-play`, `log-initMdblistScrobble-5`, `ast-237`, `ast-238`, `ast-239`, `ast-243`, `ast-246` |
| C027 | MDBList startup unresolved preserves exact requested and rejection diagnostics | `final2-log-initMdblistScrobble-3` |
| C028 | MDBList validation release while paused refreshes its session before returning without play | `final2-ref-06` |
| C029 | Secondary Simkl auth finishing paused with zero duration retains null dedup for the first real pause | `field-action`, `simkl-init-series`, `simkl-init-auth` |
| C030 | Secondary Simkl auth storage failure propagates before enablement and never becomes an HTTP failure | `simkl-init-series`, `simkl-init-auth` |
| C031 | Secondary TV scope seek forwards its target into the tracker | `simkl-seek-api-0-call`, `simkl-seek-api-0-id`, `simkl-seek-api-0-progress`, `simkl-seek-api-0-season`, `simkl-seek-api-0-episode`, `simkl-seek-capture`, `simkl-seek-position`, `simkl-seek-scale`, `simkl-seek-se`, `simkl-seek-upper`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration`, `ref-46`, `ref-47` |
| C032 | Secondary TV scrub confirm sends progress while the native pause is still suspended | `simkl-seek-api-0-call`, `simkl-seek-api-0-id`, `simkl-seek-api-0-progress`, `simkl-seek-api-0-season`, `simkl-seek-api-0-episode`, `simkl-seek-capture`, `simkl-seek-position`, `simkl-seek-scale`, `simkl-seek-se`, `simkl-seek-upper`, `simkl-seek-reverse-stop`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration`, `ref-44`, `ref-45` |
| C033 | Secondary all-tracker EOF fanout preserves ordered timer ownership and tracker-specific payloads | `simkl-stop-cancel`, `md-call-mdblistPlay-play`, `md-call-mdblistStop-complete`, `md-stop-complete`, `ref-12`, `ref-13`, `ref-14`, `ref-16`, `ref-19`, `ref-20`, `ref-21`, `ref-22`, `ref-23` |
| C034 | Secondary all-tracker dispose fanout preserves ordered timer ownership and tracker-specific payloads | `simkl-stop-cancel`, `md-call-mdblistPlay-play`, `md-stop-default`, `ref-12`, `ref-13`, `ref-14`, `ref-16`, `ref-19`, `ref-20`, `ref-32`, `ref-33` |
| C035 | Secondary all-tracker pause fanout preserves ordered timer ownership and tracker-specific payloads | `simkl-stop-cancel`, `md-call-mdblistPlay-play`, `md-call-mdblistPause-pause`, `ref-12`, `ref-13`, `ref-14`, `ref-15`, `ref-16`, `ref-19`, `ref-20` |
| C036 | Secondary all-tracker seek fanout preserves ordered timer ownership and tracker-specific payloads | `simkl-stop-cancel`, `md-call-mdblistPlay-play`, `ref-12`, `ref-13`, `ref-14`, `ref-16`, `ref-19`, `ref-20` |
| C037 | Secondary concurrent mdblist and simkl readers reset the shared identity and sibling cache | `ref-08` |
| C038 | Secondary concurrent simkl and mdblist readers reset the shared identity and sibling cache | `ref-09` |
| C039 | Secondary dispose during policy preferences await starts no player heartbeat or send | `final2-caller-init-mounted` |
| C040 | Secondary double tap left seek reaches the original tracking caller | `simkl-seek-api-0-call`, `simkl-seek-api-1-call`, `simkl-seek-api-1-id`, `simkl-seek-api-1-progress`, `simkl-seek-api-1-season`, `simkl-seek-api-1-episode`, `simkl-seek-capture`, `simkl-seek-position`, `simkl-seek-scale`, `simkl-seek-se`, `simkl-seek-upper`, `simkl-seek-stop-marker`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration`, `ref-48`, `ref-49` |
| C041 | Secondary double tap right seek reaches the original tracking caller | `simkl-seek-api-0-call`, `simkl-seek-api-0-id`, `simkl-seek-api-0-progress`, `simkl-seek-api-0-season`, `simkl-seek-api-0-episode`, `simkl-seek-capture`, `simkl-seek-position`, `simkl-seek-scale`, `simkl-seek-se`, `simkl-seek-upper`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration`, `ref-48`, `ref-49` |
| C042 | Secondary early policy await follows incoming profile credentials for the still-mounted outgoing route | `simkl-init-series`, `md-init-target`, `md-init-zero-position`, `md-init-zero-duration`, `md-init-assignment`, `md-init-play` |
| C043 | Secondary failed held checkpoint retains original tracker dedup before and after reply | `simkl-send-api-0-call`, `final-ref-11`, `ast-073` |
| C044 | Secondary failed status checkpoint retains original tracker dedup before and after reply | `simkl-send-api-0-call`, `final-ref-11`, `ast-073` |
| C045 | Secondary failed throw checkpoint retains original tracker dedup before and after reply | `simkl-send-api-0-call`, `final-ref-11`, `ast-073` |
| C046 | Secondary gated disposal still closes MDBList at its outgoing position with no Trakt or Simkl stop | `field-session`, `simkl-send-validation`, `md-updateMdblistPosition-validation`, `md-position-duration`, `md-position-update`, `ref-33`, `ref-34` |
| C047 | Secondary guide mask custom is reloaded after held local resume and late episode metadata | `final-ref-03` |
| C048 | Secondary guide mask local is reloaded after held local resume and late episode metadata | `final-ref-03` |
| C049 | Secondary guide mask smart is reloaded after held local resume and late episode metadata | `final-ref-03` |
| C050 | Secondary guide mask trakt is reloaded after held local resume and late episode metadata | `final-ref-03` |
| C051 | Secondary held Simkl auth observes false enablement and null timer before pause and late dispose completion | `field-simklScrobbleEnabled`, `field-timer`, `simkl-init-series`, `simkl-init-auth` |
| C052 | Secondary held resume pins MDBList raw initialization then persistable pause and stop diagnostics | `md-init-player-wait`, `md-init-target`, `md-init-raw-position`, `md-init-zero-position`, `md-init-zero-duration`, `md-init-assignment`, `md-init-play`, `md-mdblistPause-update`, `md-position-position`, `md-position-duration`, `md-position-update`, `md-call-mdblistPause-pause`, `md-stop-default`, `log-initMdblistScrobble-5`, `log-mdblistStop-0`, `ref-12`, `ref-13`, `ref-20`, `ast-237`, `ast-238`, `ast-239`, `ast-243`, `ast-246`, `ast-272`, `ast-273`, `ast-274`, `ast-279`, `ast-282` |
| C053 | Secondary horizontal pan completion sends the displayed seek target | `simkl-seek-api-0-call`, `simkl-seek-api-0-id`, `simkl-seek-api-0-progress`, `simkl-seek-api-0-season`, `simkl-seek-api-0-episode`, `simkl-seek-capture`, `simkl-seek-position`, `simkl-seek-scale`, `simkl-seek-se`, `simkl-seek-upper`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration`, `ref-50`, `ref-51` |
| C054 | Secondary keyboard forward seek sends the clamped target | `simkl-seek-api-0-call`, `simkl-seek-api-0-id`, `simkl-seek-api-0-progress`, `simkl-seek-api-0-season`, `simkl-seek-api-0-episode`, `simkl-seek-capture`, `simkl-seek-position`, `simkl-seek-scale`, `simkl-seek-se`, `simkl-seek-upper`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration`, `ref-53`, `ref-56` |
| C055 | Secondary keyboard rewind seek sends the clamped target | `simkl-seek-api-0-call`, `simkl-seek-api-1-call`, `simkl-seek-api-1-id`, `simkl-seek-api-1-progress`, `simkl-seek-api-1-season`, `simkl-seek-api-1-episode`, `simkl-seek-capture`, `simkl-seek-position`, `simkl-seek-scale`, `simkl-seek-se`, `simkl-seek-upper`, `simkl-seek-stop-marker`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration`, `ref-52`, `ref-54`, `ref-55`, `ref-57` |
| C056 | Secondary landed slider 80 keeps original MDBList crossing silence until exit | `simkl-seek-threshold`, `simkl-seek-reverse-stop` |
| C057 | Secondary landed slider 81 keeps original MDBList crossing silence until exit | `simkl-seek-api-0-call`, `simkl-seek-scale`, `simkl-seek-upper`, `ref-54` |
| C058 | Secondary legacy policy storage type error propagates from MDBList initialization while player failure stays caught | `final2-ref-02` |
| C059 | Secondary mdblist custom identity policy disables otherwise enabled tracking before authentication | `final-md-init-policy-content` |
| C060 | Secondary mdblist disabled at startup stays disabled after target enablement | `final2-md-init-policy` |
| C061 | Secondary mdblist disabling an active target preserves pause heartbeat seek and exit continuation | `final2-ref-02` |
| C062 | Secondary mdblist guide completion stays masked during an overlapping episode change and Trakt rewatch | `final-snapshot-mdblist-guide-mask`, `final-snapshot-mdblist-branch` |
| C063 | Secondary mdblist initialization credential gate preserves absent checkpoints | `md-init-assignment` |
| C064 | Secondary mdblist initialization episode gate preserves absent checkpoints | `md-target-se`, `md-target-unresolved`, `md-init-target`, `md-init-null-target`, `ast-225` |
| C065 | Secondary mdblist initialization flag gate preserves absent checkpoints | `md-init-flag`, `ast-206` |
| C066 | Secondary mdblist initialization identity gate preserves absent checkpoints | `md-target-capture`, `md-target-null`, `md-init-target`, `md-init-null-target`, `ast-225` |
| C067 | Secondary mdblist initialization season gate preserves absent checkpoints | `md-target-se`, `md-target-unresolved`, `md-init-target`, `md-init-null-target`, `ast-225` |
| C068 | Secondary mdblist initialization target gate preserves absent checkpoints | `md-init-policy` |
| C069 | Secondary mdblist initialization type gate preserves absent checkpoints | `md-target-series`, `md-init-target`, `md-init-null-target`, `ast-225` |
| C070 | Secondary mdblist inner snapshot policy rejects remote resume after the outer policy has been captured | `final2-snapshot-mdblist-default`, `final2-snapshot-mdblist-policy-mask` |
| C071 | Secondary mdblist launch promise is spent once and episode snapshots stay cached per bound show | `field-launchMdblistPercentSpent`, `snapshot-mdblist-identity`, `snapshot-mdblist-bind`, `snapshot-mdblist-cache`, `snapshot-mdblist-assign`, `snapshot-mdblist-se`, `snapshot-mdblist-key`, `ref-40`, `ref-41`, `ref-42`, `ast-389` |
| C072 | Secondary mdblist masked guide read still warms its snapshot for a later selected-provider resume | `final2-snapshot-mdblist-guide-bypass`, `final2-ref-43` |
| C073 | Secondary mdblist missing coordinates snapshot boundary cannot resume from malformed null keys | `final2-snapshot-mdblist-unresolved` |
| C074 | Secondary mdblist missing identity snapshot boundary cannot resume from malformed null keys | `final2-snapshot-mdblist-null-id` |
| C075 | Secondary mdblist single-file snapshot resolves effective coordinates before resuming | `snapshot-mdblist-identity`, `snapshot-mdblist-bind`, `snapshot-mdblist-assign`, `snapshot-mdblist-se`, `snapshot-mdblist-key`, `ref-42`, `ast-389` |
| C076 | Secondary mdblist snapshot custom identity arriving after outer policy capture rejects provider-owned resume | `final2-snapshot-mdblist-policy-content` |
| C077 | Secondary mdblist suspended snapshot A-B-A pins late coordinates and original identity guard | `snapshot-mdblist-identity`, `snapshot-mdblist-bind`, `snapshot-mdblist-assign`, `snapshot-mdblist-se`, `snapshot-mdblist-key`, `ref-09`, `ast-389` |
| C078 | Secondary mdblist suspended snapshot dispose pins late coordinates and original identity guard | `snapshot-mdblist-identity`, `snapshot-mdblist-bind`, `snapshot-mdblist-assign`, `snapshot-mdblist-se`, `snapshot-mdblist-key`, `ast-389` |
| C079 | Secondary mdblist suspended snapshot episode pins late coordinates and original identity guard | `snapshot-mdblist-identity`, `snapshot-mdblist-bind`, `snapshot-mdblist-assign`, `snapshot-mdblist-se`, `ast-389` |
| C080 | Secondary mdblist suspended snapshot profile pins late coordinates and original identity guard | `snapshot-mdblist-identity`, `snapshot-mdblist-bind`, `snapshot-mdblist-assign`, `snapshot-mdblist-se`, `snapshot-mdblist-key`, `ast-389` |
| C081 | Secondary mdblist suspended snapshot show pins late coordinates and original identity guard | `snapshot-mdblist-identity`, `snapshot-mdblist-bind`, `snapshot-mdblist-guard`, `snapshot-mdblist-late-guard`, `snapshot-mdblist-assign`, `snapshot-mdblist-se`, `ast-389` |
| C082 | Secondary missing session stop diagnostics retain false presence before any allocation | `final2-ast-274` |
| C083 | Secondary pause at 80 preserves Simkl strict and MDBList inclusive completion thresholds | `simkl-send-api-0-call`, `simkl-send-api-0-id`, `simkl-send-api-0-progress`, `simkl-send-api-0-season`, `simkl-send-api-0-episode`, `simkl-send-capture`, `simkl-send-percent`, `simkl-send-se`, `simkl-send-threshold`, `ast-073` |
| C084 | Secondary pause at 81 preserves Simkl strict and MDBList inclusive completion thresholds | `simkl-send-api-1-call`, `simkl-send-api-1-id`, `simkl-send-api-1-progress`, `simkl-send-api-1-season`, `simkl-send-api-1-episode`, `simkl-send-capture`, `simkl-send-percent`, `simkl-send-se`, `simkl-send-upper`, `simkl-send-pause`, `simkl-send-stop`, `ast-077` |
| C085 | Secondary protocol episode play pause exit bodies and dedup | `simkl-send-api-0-call`, `simkl-send-api-0-id`, `simkl-send-api-0-progress`, `simkl-send-api-0-season`, `simkl-send-api-0-episode`, `simkl-send-api-1-call`, `simkl-send-api-1-id`, `simkl-send-api-1-progress`, `simkl-send-api-1-season`, `simkl-send-api-1-episode`, `simkl-send-capture`, `simkl-send-percent`, `simkl-send-se`, `simkl-stop-cancel`, `md-position-duration`, `md-position-update`, `md-call-mdblistPause-pause`, `ref-01`, `ref-02`, `ref-12`, `ref-13`, `ref-20`, `ref-32`, `ast-073`, `ast-077` |
| C086 | Secondary protocol movie play pause exit bodies and dedup | `final-simkl-init-movie`, `simkl-unresolved-series`, `simkl-send-api-0-call`, `simkl-send-api-0-id`, `simkl-send-api-0-progress`, `simkl-send-api-0-season`, `simkl-send-api-0-episode`, `simkl-send-api-1-call`, `simkl-send-api-1-id`, `simkl-send-api-1-progress`, `simkl-send-api-1-season`, `simkl-send-api-1-episode`, `simkl-send-capture`, `simkl-send-percent`, `simkl-send-se`, `simkl-stop-cancel`, `md-target-capture`, `md-target-ids`, `md-target-movie`, `md-position-duration`, `md-position-update`, `md-call-mdblistPause-pause`, `ref-01`, `ref-02`, `ref-12`, `ref-13`, `ref-20`, `ref-32`, `ast-073`, `ast-077`, `ast-174` |
| C087 | Secondary seek at 80 crosses tracker thresholds and seeking back rearms checkpoints | `simkl-beat-api-1-call`, `simkl-beat-api-1-id`, `simkl-beat-api-1-progress`, `simkl-beat-api-1-season`, `simkl-beat-api-1-episode`, `simkl-beat-interval`, `simkl-beat-capture`, `simkl-beat-percent`, `simkl-beat-se`, `simkl-beat-pause-marker`, `simkl-seek-threshold`, `simkl-seek-reverse-stop`, `md-call-mdblistPlay-play`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration`, `ref-12`, `ref-13`, `ref-14`, `ref-15`, `ref-16`, `ref-19`, `ref-20`, `ref-57` |
| C088 | Secondary seek at 81 crosses tracker thresholds and seeking back rearms checkpoints | `simkl-beat-api-1-call`, `simkl-beat-api-1-id`, `simkl-beat-api-1-progress`, `simkl-beat-api-1-season`, `simkl-beat-api-1-episode`, `simkl-seek-api-0-call`, `simkl-seek-api-0-id`, `simkl-seek-api-0-progress`, `simkl-seek-api-0-season`, `simkl-seek-api-0-episode`, `simkl-seek-api-1-call`, `simkl-seek-api-1-id`, `simkl-seek-api-1-progress`, `simkl-seek-api-1-season`, `simkl-seek-api-1-episode`, `simkl-beat-interval`, `simkl-beat-capture`, `simkl-beat-percent`, `simkl-beat-se`, `simkl-beat-pause-marker`, `simkl-seek-capture`, `simkl-seek-position`, `simkl-seek-scale`, `simkl-seek-se`, `simkl-seek-upper`, `simkl-seek-stop-marker`, `simkl-seek-reverse-stop`, `simkl-seek-reverse-marker`, `md-call-mdblistPlay-play`, `md-call-mdblistScrobbleSeek-seek`, `md-seek-target`, `md-seek-duration`, `ref-12`, `ref-13`, `ref-14`, `ref-15`, `ref-16`, `ref-19`, `ref-20`, `ref-54`, `ref-57` |
| C089 | Secondary simkl custom identity policy disables otherwise enabled tracking before authentication | `final-simkl-init-policy-content` |
| C090 | Secondary simkl disabled at startup stays disabled after target enablement | `final2-simkl-init-policy`, `final-simkl-send-enabled` |
| C091 | Secondary simkl disabling an active target preserves pause heartbeat seek and exit continuation | `final2-ref-01` |
| C092 | Secondary simkl guide completion stays masked during an overlapping episode change and Trakt rewatch | `final-snapshot-simkl-guide-mask`, `final-snapshot-simkl-branch` |
| C093 | Secondary simkl initialization credential gate preserves absent checkpoints | `final-ref-10` |
| C094 | Secondary simkl initialization episode gate preserves absent checkpoints | `simkl-init-series`, `final-simkl-send-unresolved`, `final-simkl-seek-unresolved` |
| C095 | Secondary simkl initialization flag gate preserves absent checkpoints | `field-simklScrobbleEnabled`, `simkl-init-flag`, `final-ref-10` |
| C096 | Secondary simkl initialization identity gate preserves absent checkpoints | `field-simklScrobbleEnabled`, `simkl-init-id`, `final-ref-10` |
| C097 | Secondary simkl initialization season gate preserves absent checkpoints | `simkl-init-series`, `final-simkl-send-unresolved`, `final-simkl-seek-unresolved` |
| C098 | Secondary simkl initialization target gate preserves absent checkpoints | `simkl-init-policy`, `final-simkl-send-enabled`, `final-simkl-seek-enabled`, `final-ref-10` |
| C099 | Secondary simkl initialization type gate preserves absent checkpoints | `field-simklScrobbleEnabled`, `simkl-init-type`, `final-ref-10` |
| C100 | Secondary simkl inner snapshot policy rejects remote resume after the outer policy has been captured | `final2-snapshot-simkl-default`, `final2-snapshot-simkl-policy-mask` |
| C101 | Secondary simkl launch promise is spent once and episode snapshots stay cached per bound show | `field-launchSimklPercentSpent`, `snapshot-simkl-identity`, `snapshot-simkl-bind`, `snapshot-simkl-cache`, `snapshot-simkl-assign`, `snapshot-simkl-series`, `snapshot-simkl-index`, `snapshot-simkl-season`, `snapshot-simkl-episode`, `snapshot-simkl-key`, `ref-36`, `ref-37`, `ref-38`, `ast-316`, `ast-324`, `ast-329` |
| C102 | Secondary simkl masked guide read still warms its snapshot for a later selected-provider resume | `final2-snapshot-simkl-guide-bypass`, `final2-ref-39` |
| C103 | Secondary simkl missing coordinates snapshot boundary cannot resume from malformed null keys | `final2-snapshot-simkl-unresolved` |
| C104 | Secondary simkl missing identity snapshot boundary cannot resume from malformed null keys | `final2-snapshot-simkl-null-id` |
| C105 | Secondary simkl missing public guide row during snapshot storage rejects the outgoing resume | `final2-snapshot-simkl-empty` |
| C106 | Secondary simkl single-file snapshot resolves effective coordinates before resuming | `snapshot-simkl-identity`, `snapshot-simkl-bind`, `snapshot-simkl-assign`, `snapshot-simkl-fallback`, `snapshot-simkl-fallback-season`, `snapshot-simkl-fallback-episode`, `snapshot-simkl-key`, `ref-38`, `ast-316` |
| C107 | Secondary simkl snapshot custom identity arriving after outer policy capture rejects provider-owned resume | `final2-snapshot-simkl-policy-content` |
| C108 | Secondary simkl snapshot rejects the transient old index while a shorter source playlist awaits URL resolution | `final2-ast-333` |
| C109 | Secondary simkl suspended snapshot A-B-A pins late coordinates and original identity guard | `snapshot-simkl-identity`, `snapshot-simkl-bind`, `snapshot-simkl-assign`, `snapshot-simkl-series`, `snapshot-simkl-index`, `snapshot-simkl-season`, `snapshot-simkl-episode`, `snapshot-simkl-key`, `ref-08`, `ast-316`, `ast-324`, `ast-329` |
| C110 | Secondary simkl suspended snapshot dispose pins late coordinates and original identity guard | `snapshot-simkl-identity`, `snapshot-simkl-bind`, `snapshot-simkl-assign`, `snapshot-simkl-series`, `snapshot-simkl-index`, `snapshot-simkl-season`, `snapshot-simkl-episode`, `snapshot-simkl-key`, `ast-316`, `ast-324`, `ast-329` |
| C111 | Secondary simkl suspended snapshot episode pins late coordinates and original identity guard | `snapshot-simkl-identity`, `snapshot-simkl-bind`, `snapshot-simkl-assign`, `snapshot-simkl-series`, `snapshot-simkl-season`, `snapshot-simkl-episode`, `ast-316`, `ast-324`, `ast-329` |
| C112 | Secondary simkl suspended snapshot profile pins late coordinates and original identity guard | `snapshot-simkl-identity`, `snapshot-simkl-bind`, `snapshot-simkl-assign`, `snapshot-simkl-series`, `snapshot-simkl-index`, `snapshot-simkl-season`, `snapshot-simkl-episode`, `snapshot-simkl-key`, `ast-316`, `ast-324`, `ast-329` |
| C113 | Secondary simkl suspended snapshot show pins late coordinates and original identity guard | `snapshot-simkl-identity`, `snapshot-simkl-bind`, `snapshot-simkl-guard`, `snapshot-simkl-late-guard`, `snapshot-simkl-assign`, `snapshot-simkl-series`, `snapshot-simkl-season`, `snapshot-simkl-episode`, `ast-316`, `ast-324`, `ast-329` |
| C114 | Secondary zero-duration session starts MDBList on the first usable duration and Simkl on a playing edge | `simkl-init-series`, `simkl-init-auth`, `simkl-init-duration`, `md-target-capture`, `md-target-ids`, `md-target-se`, `md-target-season`, `md-target-episode`, `md-init-target`, `md-init-capability`, `md-init-assignment`, `md-init-duration`, `md-position-duration`, `md-position-update`, `md-call-mdblistPlay-play`, `ref-14`, `ref-18` |
| C115 | Simkl EOF then disposal deduplicates the already sent stop checkpoint | `final-simkl-send-dedup`, `final-simkl-send-marker` |
| C116 | Simkl auth before playing and duration stays inert until the original validation release caller | `simkl-init-series`, `ref-05` |
| C117 | Simkl auth finishing paused with positive duration does not arm a checkpoint | `simkl-init-series`, `simkl-init-auth`, `simkl-init-playing` |
| C118 | Simkl authentication inside startup validation keeps its timer absent until a decoded frame releases the gate | `final-simkl-init-validation` |
| C119 | Simkl disabled policy delivered after playing and duration cannot arm a silent heartbeat | `final2-simkl-init-enabled` |
| C120 | Simkl disposal during playing auth completion cannot create a late heartbeat | `final-simkl-init-mounted` |
| C121 | Simkl episode-only filename remains unresolved and leaves its heartbeat armed above eighty | `final2-simkl-beat-unresolved` |
| C122 | Simkl heartbeat exact interval force pause keeps live marker then stops above eighty with exact diagnostics | `simkl-beat-api-0-call`, `simkl-beat-api-0-id`, `simkl-beat-api-0-progress`, `simkl-beat-api-0-season`, `simkl-beat-api-0-episode`, `simkl-beat-api-1-call`, `simkl-beat-api-1-id`, `simkl-beat-api-1-progress`, `simkl-beat-api-1-season`, `simkl-beat-api-1-episode`, `simkl-beat-interval`, `simkl-beat-capture`, `simkl-beat-percent`, `simkl-beat-se`, `simkl-beat-threshold`, `simkl-beat-upper`, `simkl-beat-stop-marker`, `simkl-beat-stop-heartbeat`, `simkl-beat-precision`, `simkl-beat-stop-log`, `simkl-beat-pause-log`, `simkl-stop-cancel`, `ast-109`, `ast-111`, `ast-118`, `ast-119` |
| C123 | Simkl heartbeat live coordinates gate keeps original armed timer silent until disposal | `simkl-beat-interval`, `simkl-beat-se`, `simkl-beat-unresolved`, `simkl-stop-cancel` |
| C124 | Simkl heartbeat live duration gate keeps original armed timer silent until disposal | `simkl-beat-interval`, `simkl-beat-duration`, `simkl-stop-cancel`, `ast-093` |
| C125 | Simkl heartbeat live identity gate keeps original armed timer silent until disposal | `simkl-beat-interval`, `simkl-beat-id`, `simkl-stop-cancel`, `ast-088` |
| C126 | Simkl held 201 stop across dispose pins response revisions and service-owned recovery | `case-simkl-seek-api-0-call` |
| C127 | Simkl held 201 stop across profile pins response revisions and service-owned recovery | `case-simkl-seek-api-0-call` |
| C128 | Simkl held 409 stop across dispose pins response revisions and service-owned recovery | `case-simkl-seek-api-0-call` |
| C129 | Simkl held 409 stop across profile pins response revisions and service-owned recovery | `case-simkl-seek-api-0-call` |
| C130 | Simkl initialized playing owns one immediate heartbeat without a remote start | `final-simkl-init-heartbeat` |
| C131 | Simkl initially disabled policy cannot install even a silent heartbeat before any input | `final2-simkl-init-policy` |
| C132 | Simkl live heartbeat during a suspended source open rejects the paused or validation-gated renderer | `final2-simkl-beat-validation`, `final2-simkl-seek-validation` |
| C133 | Simkl live heartbeat during a suspended source pause rejects the paused or validation-gated renderer | `final2-simkl-beat-playing` |
| C134 | Simkl live null widget identity at pause never reuses its initialized identity | `simkl-send-id`, `ast-048` |
| C135 | Simkl live null widget identity at seek never reuses its initialized identity | `simkl-seek-id`, `ast-129` |
| C136 | Simkl parsed episode-only identity rejects heartbeat and pause with a missing season | `final2-simkl-unresolved-season`, `final2-simkl-unresolved-or` |
| C137 | Simkl playlist selection stops its outgoing episode and heartbeat before a held incoming open | `final-ref-26`, `final-ref-27` |
| C138 | Simkl public seek endpoints send exactly one hundred then zero and a reverse seek at eighty remains resumable | `final-simkl-seek-low`, `final-simkl-seek-high`, `final-simkl-seek-stop-dedup`, `final-simkl-seek-stop-heartbeat`, `final-simkl-seek-reverse-threshold`, `final-simkl-seek-reverse-heartbeat` |
| C139 | Simkl public seek while duration remains silent despite a threshold-sized input | `final-simkl-seek-duration`, `final-ast-134` |
| C140 | Simkl public seek while paused remains silent despite a threshold-sized input | `final-simkl-seek-playing`, `final-ast-134` |
| C141 | Simkl repeated playing notification replaces its live heartbeat without a duplicate checkpoint | `final-simkl-beat-cancel` |
| C142 | Simkl successful source validation resets a watched stop marker before the next real pause | `final2-ref-04` |

| Mutation point (original declaration:line) | Statement / branch / literal → mutation | Result / original case |
|---|---|---|
| `field-simklScrobbleEnabled` (_simklScrobbleEnabled:1487) | `false` → `true` | killed: C095, C096, C099, C051 |
| `field-launchSimklPercentSpent` (_launchSimklPercentSpent:1488) | `false` → `true` | killed: C101 |
| `field-launchMdblistPercentSpent` (_launchMdblistPercentSpent:1494) | `false` → `true` | killed: C071 |
| `field-simklEpisodeProgress` (_simklEpisodeProgress:1491) | `_simklEpisodeProgress;` → `_simklEpisodeProgress = {};` | equivalent: All readers bind a non-null series identity before reading this cache. The State binder starts with null identity and resets all three caches on that first identity. A null identity returns before accessing the cache. No asynchronous gap occurs between bind and the cache test. |
| `field-mdblistEpisodeProgress` (_mdblistEpisodeProgress:1492) | `_mdblistEpisodeProgress;` → `_mdblistEpisodeProgress = {};` | equivalent: Same shared State-owned identity-binder invariant as Simkl: the first non-null identity clears this cache before reading, even if another tracker binds first; a null identity returns before reading. |
| `field-action` (_simklLastScrobbleAction:1495) | `_simklLastScrobbleAction;` → `_simklLastScrobbleAction = 'pause';` | killed: C029 |
| `field-timer` (_simklHeartbeatTimer:1496) | `Timer? _simklHeartbeatTimer;` → `late Timer? _simklHeartbeatTimer;` | killed: C051 |
| `field-session` (_mdblistSession:1497) | `MdblistScrobbleSession? _mdblistSession;` → `late MdblistScrobbleSession? _mdblistSession;` | killed: C046, C026, C025 |
| `simkl-init-flag` (_initSimklScrobble:1803) | `if (!widget.simklScrobble) return;` → `` | killed: C095 |
| `simkl-init-id` (_initSimklScrobble:1804) | `if (widget.contentImdbId == null) return;` → `` | killed: C096 |
| `simkl-init-type` (_initSimklScrobble:1805) | `if (widget.contentType != 'movie' && widget.contentType != 'series') return;` → `` | killed: C099 |
| `simkl-init-movie` (_initSimklScrobble:1805) | `widget.contentType != 'movie'` → `true` | killed: C086 |
| `simkl-init-series` (_initSimklScrobble:1805) | `widget.contentType != 'series'` → `true` | killed: C042, C097, C094, C051, C029, C030, C116, C117, C114 |
| `simkl-init-policy-content` (_initSimklScrobble:1807) | `_effectiveContentImdbId` → `null` | killed: C089 |
| `simkl-init-policy` (_initSimklScrobble:1810) | `policy.scrobbles(TrackingSource.simkl) &&` → `true &&` | killed: C131, C090 |
| `simkl-init-auth` (_initSimklScrobble:1811) | `await SimklService.instance.isAuthenticated()` → `true` | killed: C051, C029, C030, C117, C114 |
| `simkl-init-mounted` (_initSimklScrobble:1812) | `if (!mounted) return;` → `` | killed: C120 |
| `simkl-init-validation` (_initSimklScrobble:1822) | `!_validationGateActive &&` → `true &&` | killed: C118 |
| `simkl-init-enabled` (_initSimklScrobble:1823) | `_simklScrobbleEnabled &&` → `true &&` | killed: C119 |
| `simkl-init-playing` (_initSimklScrobble:1824) | `_isPlaying &&` → `true &&` | killed: C117 |
| `simkl-init-duration` (_initSimklScrobble:1825) | `_duration > Duration.zero` → `true` | killed: C114 |
| `simkl-init-marker` (_initSimklScrobble:1826) | `_simklLastScrobbleAction = 'start';` → `` | equivalent: At original init completion the marker is null unless a live playing or validation-release caller already stamped start. Init stamp start versus null cannot change a pause/stop caller dedup check: both differ from pause/stop. No live caller passes start. The first pause/stop writes its action; heartbeat and subsequent playing overwrite the marker independently. |
| `simkl-init-heartbeat` (_initSimklScrobble:1827) | `_startSimklHeartbeat();` → `` | killed: C130 |
| `simkl-unresolved-series` (_simklSeriesSEUnresolved:1837) | `widget.contentType == 'series'` → `true` | killed: C086 |
| `simkl-unresolved-season` (_simklSeriesSEUnresolved:1838) | `se.season == null` → `false` | killed: C136 |
| `simkl-unresolved-episode` (_simklSeriesSEUnresolved:1838) | `se.episode == null` → `false` | equivalent: The retained resolver prefers parsed playlist coordinates only as a complete pair, then explicit launch coordinates only as a complete pair. Filename parsing uses bounded numeric pair patterns, episode-only patterns (season can remain null), anime (both), or special content (both). It cannot produce non-null season with null episode. Thus episode-null implies season-null and the unmodified season operand still rejects every reachable unresolved record. |
| `simkl-unresolved-or` (_simklSeriesSEUnresolved:1838) | `\|\|` → `&&` | killed: C136 |
| `simkl-send-api-0-call` (_simklScrobble:1862) | `SimklService.instance.scrobblePause(           imdbId,           progress,           season: s…` → `` | killed: C085, C086, C083, C044, C045, C043 |
| `simkl-send-api-0-id` (_simklScrobble:1862) | `SimklService.instance.scrobblePause(           imdbId,           progress,           season: s…` → `SimklService.instance.scrobblePause(           'tt5999999',           progress,           seas…` | killed: C085, C086, C083 |
| `simkl-send-api-0-progress` (_simklScrobble:1862) | `SimklService.instance.scrobblePause(           imdbId,           progress,           season: s…` → `SimklService.instance.scrobblePause(           imdbId,           0.0,           season: se.sea…` | killed: C085, C086, C083 |
| `simkl-send-api-0-season` (_simklScrobble:1862) | `SimklService.instance.scrobblePause(           imdbId,           progress,           season: s…` → `SimklService.instance.scrobblePause(           imdbId,           progress,           season: 9…` | killed: C085, C086, C083 |
| `simkl-send-api-0-episode` (_simklScrobble:1862) | `SimklService.instance.scrobblePause(           imdbId,           progress,           season: s…` → `SimklService.instance.scrobblePause(           imdbId,           progress,           season: s…` | killed: C085, C086, C083 |
| `simkl-send-api-1-call` (_simklScrobble:1870) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `` | killed: C085, C086, C084 |
| `simkl-send-api-1-id` (_simklScrobble:1870) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `SimklService.instance.scrobbleStop(           'tt5999999',           progress,           seaso…` | killed: C085, C086, C084 |
| `simkl-send-api-1-progress` (_simklScrobble:1870) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `SimklService.instance.scrobbleStop(           imdbId,           0.0,           season: se.seas…` | killed: C085, C086, C084 |
| `simkl-send-api-1-season` (_simklScrobble:1870) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: 99…` | killed: C085, C086, C084 |
| `simkl-send-api-1-episode` (_simklScrobble:1870) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` | killed: C085, C086, C084 |
| `simkl-send-break-0` (_simklScrobble:1868) | `break;` → `// implicit switch termination` | equivalent: Dart 3 nonempty switch cases implicitly terminate. Removing this terminal break leaves the same pause call and termination, without fallthrough. |
| `simkl-send-break-1` (_simklScrobble:1876) | `break;` → `// implicit switch termination` | equivalent: Dart 3 nonempty switch cases implicitly terminate. Removing this terminal break leaves the same stop call and termination. |
| `simkl-beat-api-0-call` (_startSimklHeartbeat:1902) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `` | killed: C122 |
| `simkl-beat-api-0-id` (_startSimklHeartbeat:1902) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `SimklService.instance.scrobbleStop(           'tt5999999',           progress,           seaso…` | killed: C122 |
| `simkl-beat-api-0-progress` (_startSimklHeartbeat:1902) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `SimklService.instance.scrobbleStop(           imdbId,           0.0,           season: se.seas…` | killed: C122 |
| `simkl-beat-api-0-season` (_startSimklHeartbeat:1902) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: 99…` | killed: C122 |
| `simkl-beat-api-0-episode` (_startSimklHeartbeat:1902) | `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` → `SimklService.instance.scrobbleStop(           imdbId,           progress,           season: se…` | killed: C122 |
| `simkl-beat-api-1-call` (_startSimklHeartbeat:1921) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `` | killed: C087, C088, C122 |
| `simkl-beat-api-1-id` (_startSimklHeartbeat:1921) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `SimklService.instance.scrobblePause(         'tt5999999',         progress,         season: se…` | killed: C087, C088, C122 |
| `simkl-beat-api-1-progress` (_startSimklHeartbeat:1921) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `SimklService.instance.scrobblePause(         imdbId,         0.0,         season: se.season,  …` | killed: C087, C088, C122 |
| `simkl-beat-api-1-season` (_startSimklHeartbeat:1921) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `SimklService.instance.scrobblePause(         imdbId,         progress,         season: 99,    …` | killed: C087, C088, C122 |
| `simkl-beat-api-1-episode` (_startSimklHeartbeat:1921) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` | killed: C087, C088, C122 |
| `simkl-seek-api-0-call` (_simklScrobbleSeek:1959) | `SimklService.instance.scrobbleStop(         imdbId,         progress,         season: se.seaso…` → `` | killed: C126, C127, C128, C129 |
| `simkl-seek-api-0-id` (_simklScrobbleSeek:1959) | `SimklService.instance.scrobbleStop(         imdbId,         progress,         season: se.seaso…` → `SimklService.instance.scrobbleStop(         'tt5999999',         progress,         season: se.…` | killed: C088, C054, C041, C053, C031, C032 |
| `simkl-seek-api-0-progress` (_simklScrobbleSeek:1959) | `SimklService.instance.scrobbleStop(         imdbId,         progress,         season: se.seaso…` → `SimklService.instance.scrobbleStop(         imdbId,         0.0,         season: se.season,   …` | killed: C088, C054, C041, C053, C031, C032 |
| `simkl-seek-api-0-season` (_simklScrobbleSeek:1959) | `SimklService.instance.scrobbleStop(         imdbId,         progress,         season: se.seaso…` → `SimklService.instance.scrobbleStop(         imdbId,         progress,         season: 99,     …` | killed: C088, C054, C041, C053, C031, C032 |
| `simkl-seek-api-0-episode` (_simklScrobbleSeek:1959) | `SimklService.instance.scrobbleStop(         imdbId,         progress,         season: se.seaso…` → `SimklService.instance.scrobbleStop(         imdbId,         progress,         season: se.seaso…` | killed: C088, C054, C041, C053, C031, C032 |
| `simkl-seek-api-1-call` (_simklScrobbleSeek:1971) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `` | killed: C088, C055, C040 |
| `simkl-seek-api-1-id` (_simklScrobbleSeek:1971) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `SimklService.instance.scrobblePause(         'tt5999999',         progress,         season: se…` | killed: C088, C055, C040 |
| `simkl-seek-api-1-progress` (_simklScrobbleSeek:1971) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `SimklService.instance.scrobblePause(         imdbId,         0.0,         season: se.season,  …` | killed: C088, C055, C040 |
| `simkl-seek-api-1-season` (_simklScrobbleSeek:1971) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `SimklService.instance.scrobblePause(         imdbId,         progress,         season: 99,    …` | killed: C088, C055, C040 |
| `simkl-seek-api-1-episode` (_simklScrobbleSeek:1971) | `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` → `SimklService.instance.scrobblePause(         imdbId,         progress,         season: se.seas…` | killed: C088, C055, C040 |
| `simkl-send-validation` (_simklScrobble:1841) | `if (_validationGateActive) return;` → `` | killed: C046 |
| `simkl-send-enabled` (_simklScrobble:1842) | `!_simklScrobbleEnabled \|\| widget.contentImdbId == null` → `widget.contentImdbId == null` | killed: C098, C090 |
| `simkl-send-id` (_simklScrobble:1842) | `!_simklScrobbleEnabled \|\| widget.contentImdbId == null` → `!_simklScrobbleEnabled` | killed: C134 |
| `simkl-send-capture` (_simklScrobble:1843) | `final imdbId = widget.contentImdbId!;` → `final imdbId = 'tt5999999';` | killed: C085, C086, C083, C084 |
| `simkl-send-percent` (_simklScrobble:1844) | `_trakt.traktProgress()` → `0.0` | killed: C085, C086, C083, C084 |
| `simkl-send-se` (_simklScrobble:1845) | `_traktSeasonEpisode()` → `(season: 99, episode: 99)` | killed: C085, C086, C083, C084 |
| `simkl-send-unresolved` (_simklScrobble:1846) | `if (_simklSeriesSEUnresolved(se)) return;` → `` | killed: C097, C094 |
| `simkl-send-threshold` (_simklScrobble:1849) | `progress > 80` → `progress >= 80` | killed: C083 |
| `simkl-send-upper` (_simklScrobble:1849) | `progress > 80` → `progress > 81` | killed: C084 |
| `simkl-send-pause` (_simklScrobble:1849) | `action == 'pause'` → `false` | killed: C084 |
| `simkl-send-stop` (_simklScrobble:1850) | `action = 'stop';` → `action = 'pause';` | killed: C084 |
| `simkl-send-dedup` (_simklScrobble:1852) | `if (_simklLastScrobbleAction == action) return;` → `` | killed: C115 |
| `simkl-send-marker` (_simklScrobble:1853) | `_simklLastScrobbleAction = action;` → `` | killed: C115 |
| `simkl-send-start-intent` (_simklScrobble:1849) | `action == 'start'` → `false` | dormant: All original live callers pass pause or stop; playing writes the start marker directly. Defensive start intent has no original caller. |
| `simkl-send-start-case` (_simklScrobble:1860) | `case 'start':` → `` | dormant: Same dormant defensive start intent; shared pause body remains live. |
| `simkl-beat-cancel` (_startSimklHeartbeat:1888) | `_simklHeartbeatTimer?.cancel();` → `` | killed: C141 |
| `simkl-beat-interval` (_startSimklHeartbeat:1889) | `minutes: 2` → `minutes: 1` | killed: C087, C088, C122, C124, C125, C123 |
| `simkl-beat-validation` (_startSimklHeartbeat:1890) | `_validationGateActive \|\|` → `false \|\|` | killed: C132 |
| `simkl-beat-id` (_startSimklHeartbeat:1892) | `widget.contentImdbId == null` → `false` | killed: C125 |
| `simkl-beat-playing` (_startSimklHeartbeat:1895) | `!_isPlaying \|\| _duration.inMilliseconds <= 0` → `_duration.inMilliseconds <= 0` | killed: C133 |
| `simkl-beat-duration` (_startSimklHeartbeat:1895) | `!_isPlaying \|\| _duration.inMilliseconds <= 0` → `!_isPlaying` | killed: C124 |
| `simkl-beat-capture` (_startSimklHeartbeat:1896) | `final imdbId = widget.contentImdbId!;` → `final imdbId = 'tt5999999';` | killed: C087, C088, C122 |
| `simkl-beat-percent` (_startSimklHeartbeat:1897) | `_trakt.traktProgress()` → `0.0` | killed: C087, C088, C122 |
| `simkl-beat-se` (_startSimklHeartbeat:1898) | `_traktSeasonEpisode()` → `(season: 99, episode: 99)` | killed: C087, C088, C122, C123 |
| `simkl-beat-unresolved` (_startSimklHeartbeat:1899) | `if (_simklSeriesSEUnresolved(se)) return;` → `` | killed: C121 |
| `simkl-beat-threshold` (_startSimklHeartbeat:1900) | `progress > 80` → `progress >= 80` | killed: C122 |
| `simkl-beat-upper` (_startSimklHeartbeat:1900) | `progress > 80` → `progress > 81` | killed: C122 |
| `simkl-beat-stop-marker` (_startSimklHeartbeat:1901) | `_simklLastScrobbleAction = 'stop';` → `` | killed: C122 |
| `simkl-beat-stop-heartbeat` (_startSimklHeartbeat:1911) | `_stopSimklHeartbeat();` → `` | killed: C122 |
| `simkl-beat-pause-marker` (_startSimklHeartbeat:1920) | `_simklLastScrobbleAction = 'start';` → `_simklLastScrobbleAction = 'pause';` | killed: C087, C088 |
| `simkl-beat-precision` (_startSimklHeartbeat:1909) | `toStringAsFixed(1)` → `toStringAsFixed(2)` | killed: C122 |
| `simkl-beat-stop-log` (_startSimklHeartbeat:1909) | `Simkl: Heartbeat stop at` → `Simkl: Changed stop at` | killed: C122 |
| `simkl-beat-pause-log` (_startSimklHeartbeat:1928) | `Simkl: Heartbeat pause checkpoint at` → `Simkl: Changed pause at` | killed: C122 |
| `simkl-beat-enabled` (_startSimklHeartbeat:1891) | `!_simklScrobbleEnabled \|\|` → `false \|\|` | equivalent: The only assignments of enablement are false initializer and awaited one-time init result. Every live timer armer requires that result true (init, validation release, playing subscription, or seek past an earlier tracked stop); no later path assigns false. Policy changes do not change the field. Disabled-at-start has no armed timer; disabled-mid-session retains true. |
| `simkl-stop-cancel` (_stopSimklHeartbeat:1934) | `_simklHeartbeatTimer?.cancel();` → `` | killed: C035, C036, C033, C034, C085, C086, C122, C124, C125, C123 |
| `simkl-stop-null` (_stopSimklHeartbeat:1935) | `_simklHeartbeatTimer = null;` → `` | equivalent: Only cancel and overwrite access this timer pointer. Timer.cancel is idempotent; keeping an inactive pointer changes neither scheduling nor callback delivery, and the next armer overwrites it. |
| `simkl-seek-validation` (_simklScrobbleSeek:1946) | `if (_validationGateActive) return;` → `` | killed: C132 |
| `simkl-seek-enabled` (_simklScrobbleSeek:1947) | `!_simklScrobbleEnabled \|\| widget.contentImdbId == null` → `widget.contentImdbId == null` | killed: C098 |
| `simkl-seek-id` (_simklScrobbleSeek:1947) | `!_simklScrobbleEnabled \|\| widget.contentImdbId == null` → `!_simklScrobbleEnabled` | killed: C135 |
| `simkl-seek-playing` (_simklScrobbleSeek:1948) | `!_isPlaying \|\| _duration.inMilliseconds <= 0` → `_duration.inMilliseconds <= 0` | killed: C140 |
| `simkl-seek-duration` (_simklScrobbleSeek:1948) | `!_isPlaying \|\| _duration.inMilliseconds <= 0` → `!_isPlaying` | killed: C139 |
| `simkl-seek-capture` (_simklScrobbleSeek:1949) | `final imdbId = widget.contentImdbId!;` → `final imdbId = 'tt5999999';` | killed: C088, C055, C040, C054, C041, C053, C031, C032 |
| `simkl-seek-position` (_simklScrobbleSeek:1951) | `seekTarget.inMilliseconds` → `_position.inMilliseconds` | killed: C088, C055, C040, C054, C041, C053, C031, C032 |
| `simkl-seek-scale` (_simklScrobbleSeek:1951) | `* 100` → `* 10` | killed: C088, C057, C055, C040, C054, C041, C053, C031, C032 |
| `simkl-seek-low` (_simklScrobbleSeek:1952) | `0.0,           100.0` → `1.0,           100.0` | killed: C138 |
| `simkl-seek-high` (_simklScrobbleSeek:1952) | `0.0,           100.0` → `0.0,           90.0` | killed: C138 |
| `simkl-seek-se` (_simklScrobbleSeek:1955) | `_traktSeasonEpisode()` → `(season: 99, episode: 99)` | killed: C088, C055, C040, C054, C041, C053, C031, C032 |
| `simkl-seek-unresolved` (_simklScrobbleSeek:1956) | `if (_simklSeriesSEUnresolved(se)) return;` → `` | killed: C097, C094 |
| `simkl-seek-threshold` (_simklScrobbleSeek:1957) | `progress > 80` → `progress >= 80` | killed: C087, C056 |
| `simkl-seek-upper` (_simklScrobbleSeek:1957) | `progress > 80` → `progress > 81` | killed: C088, C057, C055, C040, C054, C041, C053, C031, C032 |
| `simkl-seek-stop-dedup` (_simklScrobbleSeek:1957) | `_simklLastScrobbleAction != 'stop'` → `true` | killed: C138 |
| `simkl-seek-stop-marker` (_simklScrobbleSeek:1958) | `_simklLastScrobbleAction = 'stop';` → `` | killed: C088, C055, C040 |
| `simkl-seek-stop-heartbeat` (_simklScrobbleSeek:1965) | `_stopSimklHeartbeat();` → `` | killed: C138 |
| `simkl-seek-reverse-threshold` (_simklScrobbleSeek:1966) | `progress <= 80` → `progress < 80` | killed: C138 |
| `simkl-seek-reverse-stop` (_simklScrobbleSeek:1966) | `_simklLastScrobbleAction == 'stop'` → `true` | killed: C087, C088, C056, C032 |
| `simkl-seek-reverse-marker` (_simklScrobbleSeek:1970) | `_simklLastScrobbleAction = 'pause';` → `` | killed: C088 |
| `simkl-seek-reverse-heartbeat` (_simklScrobbleSeek:1977) | `_startSimklHeartbeat();` → `` | killed: C138 |
| `md-target-capture` (_mdblistTarget:1982) | `final imdbId = widget.contentImdbId;` → `final imdbId = 'tt5999999';` | killed: C066, C019, C018, C020, C086, C017, C114, C004, C003 |
| `md-target-null` (_mdblistTarget:1983) | `if (imdbId == null \|\| imdbId.isEmpty) return null;` → `if (imdbId == null \|\| imdbId.isEmpty) throw StateError('target');` | killed: C066 |
| `md-target-empty` (_mdblistTarget:1983) | `imdbId == null \|\| imdbId.isEmpty` → `imdbId == null` | killed: C024 |
| `md-target-ids` (_mdblistTarget:1984) | `MdblistMediaIds.forContent(imdbId)` → `MdblistMediaIds.forContent('tt5999999')` | killed: C019, C018, C020, C086, C017, C114, C004, C003 |
| `md-target-movie` (_mdblistTarget:1985) | `widget.contentType == 'movie'` → `false` | killed: C086 |
| `md-target-series` (_mdblistTarget:1988) | `if (widget.contentType != 'series') return null;` → `` | killed: C069 |
| `md-target-se` (_mdblistTarget:1989) | `_traktSeasonEpisode()` → `(season: 99, episode: 99)` | killed: C067, C064, C019, C018, C020, C017, C114, C004 |
| `md-target-unresolved` (_mdblistTarget:1990) | `if (se.season == null \|\| se.episode == null) return null;` → `if (se.season == null \|\| se.episode == null) throw StateError('coordinates');` | killed: C067, C064 |
| `md-target-season` (_mdblistTarget:1993) | `season: se.season!` → `season: 99` | killed: C019, C018, C020, C017, C114, C004 |
| `md-target-episode` (_mdblistTarget:1994) | `episode: se.episode!` → `episode: 99` | killed: C019, C018, C020, C017, C114, C004 |
| `md-init-flag` (_initMdblistScrobble:2004) | `!widget.mdblistScrobble \|\| !kMdblistEnabled` → `!kMdblistEnabled` | killed: C065 |
| `md-init-policy-content` (_initMdblistScrobble:2009) | `_effectiveContentImdbId` → `null` | killed: C059 |
| `md-init-policy` (_initMdblistScrobble:2011) | `if (!policy.scrobbles(TrackingSource.mdblist)) return;` → `` | killed: C060 |
| `md-init-player-wait` (_initMdblistScrobble:2019) | `await _playerInitializationFuture;` → `` | killed: C052, C026, C025, C015 |
| `md-init-target` (_initMdblistScrobble:2030) | `final target = _mdblistTarget();` → `final target = MdblistScrobbleTarget.movie(MdblistMediaIds.forContent('tt5999999'));` | killed: C042, C066, C069, C067, C064, C052, C114, C026, C004, C003 |
| `md-init-null-target` (_initMdblistScrobble:2031) | `if (target == null) {` → `if (target == null) { throw StateError('missing target');` | killed: C066, C069, C067, C064 |
| `md-init-capability` (_initMdblistScrobble:2035) | `final capability = await MdblistService.instance         .capturePlaybackCapability();` → `final capability = null;` | killed: C114, C004, C003, C002 |
| `md-init-late-target` (_initMdblistScrobble:2043) | `target: target,` → `target: _mdblistTarget()!,` | killed: C004 |
| `md-init-session-capability` (_initMdblistScrobble:2044) | `capability: capability,` → `capability: null,` | killed: C003 |
| `md-init-raw-position` (_initMdblistScrobble:2046) | `session.updatePosition(_position, _duration);` → `session.updatePosition(_persistablePosition, _duration);` | killed: C052 |
| `md-init-zero-position` (_initMdblistScrobble:2046) | `session.updatePosition(_position, _duration);` → `session.updatePosition(Duration.zero, _duration);` | killed: C042, C052, C026, C004 |
| `md-init-zero-duration` (_initMdblistScrobble:2046) | `session.updatePosition(_position, _duration);` → `session.updatePosition(_position, Duration.zero);` | killed: C042, C052, C026, C004 |
| `md-init-assignment` (_initMdblistScrobble:2047) | `_mdblistSession = session;` → `` | killed: C042, C063, C052, C114 |
| `md-init-validation` (_initMdblistScrobble:2054) | `!_validationGateActive &&` → `true &&` | killed: C012, C013 |
| `md-init-playing` (_initMdblistScrobble:2054) | `_isPlaying &&` → `true &&` | killed: C001 |
| `md-init-duration` (_initMdblistScrobble:2054) | `_duration > Duration.zero` → `true` | killed: C114 |
| `md-init-play` (_initMdblistScrobble:2055) | `session.play();` → `` | killed: C042, C052, C026, C004, C003 |
| `md-init-mounted-0` (_initMdblistScrobble:2024) | `if (!mounted)` → `if (false)` | killed: C006 |
| `md-init-mounted-1` (_initMdblistScrobble:2037) | `if (!mounted)` → `if (false)` | killed: C002 |
| `md-init-player-catch` (_initMdblistScrobble:2018) | `try {       await _playerInitializationFuture;     } catch (e) {       debugPrint('[MDBListDia…` → `await _playerInitializationFuture;` | killed: C015 |
| `md-init-feature-flag` (_initMdblistScrobble:2004) | `!widget.mdblistScrobble \|\| !kMdblistEnabled` → `!widget.mdblistScrobble` | equivalent: kMdblistEnabled is a top-level final bool initialized true at original mdblist_service.dart:26. No test seam, build flag, setter or other assignment can make it false. |
| `md-updateMdblistPosition-validation` (_updateMdblistPosition:2060) | `if (_validationGateActive) return;` → `` | killed: C046 |
| `md-mdblistPlay-validation` (_mdblistPlay:2066) | `if (_validationGateActive) return;` → `` | killed: C012 |
| `md-mdblistPlay-update` (_mdblistPlay:2067) | `_updateMdblistPosition();` → `` | killed: C011 |
| `md-mdblistPause-validation` (_mdblistPause:2072) | `if (_validationGateActive) return;` → `` | equivalent: The only original caller is the playing subscription, inside the synchronous !validationGateActive && !p && wasPlaying && !isTransitioning branch. No await or callback occurs between that gate and this call; the gate cannot become true before the helper reads it. Removing the inner guard leaves all original calls unchanged. The move still retains the redundant guard verbatim. |
| `md-mdblistPause-update` (_mdblistPause:2073) | `_updateMdblistPosition();` → `` | killed: C052 |
| `md-mdblistStop-validation` (_mdblistStop:2078) | `if (_validationGateActive) return;` → `` | killed: C012, C014 |
| `md-mdblistStop-update` (_mdblistStop:2079) | `_updateMdblistPosition();` → `` | killed: C010 |
| `md-mdblistScrobbleSeek-validation` (_mdblistScrobbleSeek:2094) | `if (_validationGateActive) return;` → `` | killed: C014 |
| `md-switchMdblistTarget-validation` (_switchMdblistTarget:2114) | `if (_validationGateActive) return;` → `` | killed: C017 |
| `md-position-position` (_updateMdblistPosition:2062) | `_persistablePosition` → `_position` | killed: C052 |
| `md-position-duration` (_updateMdblistPosition:2062) | `_duration` → `Duration.zero` | killed: C052, C046, C085, C086, C114 |
| `md-position-update` (_updateMdblistPosition:2062) | `_mdblistSession?.updatePosition(_persistablePosition, _duration);` → `` | killed: C052, C046, C085, C086, C114 |
| `md-call-mdblistPlay-play` (_mdblistPlay:2068) | `_mdblistSession?.play();` → `` | killed: C035, C036, C033, C034, C087, C088, C114 |
| `md-call-mdblistPause-pause` (_mdblistPause:2074) | `_mdblistSession?.pause();` → `` | killed: C035, C052, C085, C086 |
| `md-call-mdblistStop-complete` (_mdblistStop:2087) | `_mdblistSession?.complete();` → `` | killed: C033 |
| `md-call-mdblistStop-exit` (_mdblistStop:2089) | `_mdblistSession?.exit();` → `` | killed: C016 |
| `md-call-mdblistScrobbleSeek-seek` (_mdblistScrobbleSeek:2095) | `_mdblistSession?.seek(target, _duration);` → `` | killed: C087, C088, C055, C040, C054, C041, C053, C031, C032 |
| `md-stop-complete` (_mdblistStop:2086) | `if (complete)` → `if (false)` | killed: C033 |
| `md-stop-default` (_mdblistStop:2077) | `bool complete = false` → `bool complete = true` | killed: C034, C052, C005 |
| `md-seek-target` (_mdblistScrobbleSeek:2095) | `seek(target, _duration)` → `seek(_position, _duration)` | killed: C087, C088, C055, C040, C054, C041, C053, C031, C032 |
| `md-seek-duration` (_mdblistScrobbleSeek:2095) | `seek(target, _duration)` → `seek(target, Duration.zero)` | killed: C087, C088, C055, C040, C054, C041, C053, C031, C032 |
| `md-switch-target` (_switchMdblistTarget:2115) | `final target = _mdblistTarget();` → `final target = MdblistScrobbleTarget.movie(MdblistMediaIds.forContent('tt5999999'));` | killed: C019 |
| `md-switch-null` (_switchMdblistTarget:2116) | `if (target == null) {` → `if (target == null) { throw StateError('target');` | killed: C007 |
| `md-switch-exit` (_switchMdblistTarget:2117) | `_mdblistSession?.exit();` → `` | killed: C007 |
| `md-switch-call` (_switchMdblistTarget:2120) | `await _mdblistSession?.switchTarget(target);` → `` | killed: C019 |
| `md-switch-await` (_switchMdblistTarget:2120) | `await _mdblistSession?.switchTarget(target);` → `_mdblistSession?.switchTarget(target);` | killed: C019 |
| `snapshot-simkl-default` (_currentEpisodeSimklPercent:2137) | `bool forGuide = false` → `bool forGuide = true` | killed: C100 |
| `snapshot-simkl-policy-content` (_currentEpisodeSimklPercent:2139) | `_effectiveContentImdbId` → `null` | killed: C107 |
| `snapshot-simkl-policy-mask` (_currentEpisodeSimklPercent:2141) | `if (!forGuide && !policy.progressFrom(TrackingSource.simkl)) return null;` → `` | killed: C100 |
| `snapshot-simkl-guide-bypass` (_currentEpisodeSimklPercent:2141) | `!forGuide && !policy.progressFrom` → `!policy.progressFrom` | killed: C102 |
| `snapshot-simkl-identity` (_currentEpisodeSimklPercent:2142) | `final imdbId = _currentSeriesImdbId;` → `final imdbId = 'tt5999999';` | killed: C111, C113, C109, C112, C110, C101, C106 |
| `snapshot-simkl-null-id` (_currentEpisodeSimklPercent:2143) | `if (imdbId == null) return null;` → `if (imdbId == null) throw StateError('snapshot identity');` | killed: C104 |
| `snapshot-simkl-bind` (_currentEpisodeSimklPercent:2144) | `_bindEpisodeTrackerProgressIdentity(imdbId);` → `` | killed: C111, C113, C109, C112, C110, C101, C106 |
| `snapshot-simkl-cache` (_currentEpisodeSimklPercent:2148) | `if (_simklEpisodeProgress == null)` → `if (true)` | killed: C101 |
| `snapshot-simkl-guard` (_currentEpisodeSimklPercent:2153) | `if (_episodeTrackerProgressImdbId != imdbId) return null;` → `` | killed: C113 |
| `snapshot-simkl-late-guard` (_currentEpisodeSimklPercent:2153) | `_episodeTrackerProgressImdbId != imdbId` → `_episodeTrackerProgressImdbId != _currentSeriesImdbId` | killed: C113 |
| `snapshot-simkl-assign` (_currentEpisodeSimklPercent:2154) | `_simklEpisodeProgress = loaded;` → `_simklEpisodeProgress = {};` | killed: C111, C113, C109, C112, C110, C101, C106 |
| `snapshot-simkl-guide-mask` (_currentEpisodeSimklPercent:2185) | `policy.guideProgressFrom(TrackingSource.simkl, percent)` → `percent` | killed: C092 |
| `snapshot-simkl-branch` (_currentEpisodeSimklPercent:2184) | `return forGuide` → `return !forGuide` | killed: C092 |
| `snapshot-simkl-series` (_currentEpisodeSimklPercent:2160) | `seriesPlaylist != null && seriesPlaylist.isSeries` → `seriesPlaylist != null && !seriesPlaylist.isSeries` | killed: C111, C113, C109, C112, C110, C101 |
| `snapshot-simkl-empty` (_currentEpisodeSimklPercent:2174) | `if (currentEpisode == null) return null;` → `if (currentEpisode == null) throw StateError('missing row');` | killed: C105 |
| `snapshot-simkl-index` (_currentEpisodeSimklPercent:2169) | `candidate.originalIndex == _currentIndex` → `candidate.originalIndex == 0` | killed: C109, C112, C110, C101 |
| `snapshot-simkl-season` (_currentEpisodeSimklPercent:2175) | `season = currentEpisode.seriesInfo.season;` → `season = 99;` | killed: C111, C113, C109, C112, C110, C101 |
| `snapshot-simkl-episode` (_currentEpisodeSimklPercent:2176) | `episode = currentEpisode.seriesInfo.episode;` → `episode = 99;` | killed: C111, C113, C109, C112, C110, C101 |
| `snapshot-simkl-fallback` (_currentEpisodeSimklPercent:2177) | `_effectiveContentType == 'series'` → `_effectiveContentType == 'movie'` | killed: C106 |
| `snapshot-simkl-fallback-season` (_currentEpisodeSimklPercent:2178) | `season = _effectiveContentSeason;` → `season = 99;` | killed: C106 |
| `snapshot-simkl-fallback-episode` (_currentEpisodeSimklPercent:2179) | `episode = _effectiveContentEpisode;` → `episode = 99;` | killed: C106 |
| `snapshot-simkl-unresolved` (_currentEpisodeSimklPercent:2181) | `if (season == null \|\| episode == null) return null;` → `if (season == null \|\| episode == null) throw StateError('snapshot coordinates');` | killed: C103 |
| `snapshot-simkl-key` (_currentEpisodeSimklPercent:2183) | `['${season}_$episode']` → `['${episode}_$season']` | killed: C109, C112, C110, C101, C106 |
| `snapshot-simkl-bounds` (_currentEpisodeSimklPercent:2164) | `_currentIndex >= playlist.length` → `false` | equivalent: Production SeriesEpisode rows originate from valid indices of the active playlist. An out-of-range index cannot equal any row originalIndex; after the synchronous scan the missing-row guard returns null. No await exists inside index validation/scan. |
| `snapshot-simkl-negative` (_currentEpisodeSimklPercent:2163) | `_currentIndex < 0` → `false` | equivalent: Same invariant: production row originalIndex is non-negative. With an invalid negative index, the following missing-row guard returns null. SeriesBrowser placeholders with originalIndex=-1 are local merged display rows and are never added to seriesPlaylist.allEpisodes. |
| `snapshot-simkl-break` (_currentEpisodeSimklPercent:2171) | `break;` → `` | equivalent: Production row construction assigns unique original indices; metadata updates replace only seriesInfo, keeping originalIndex. At most one candidate matches. Continuing the loop cannot overwrite the unique matching row. The factory keeps each valid index in either the normal season or the alternate-version season, never both; its fallback and movie paths also emit one row per valid index. Missing-episode placeholders remain in the browser-only merged display list. |
| `snapshot-mdblist-default` (_currentEpisodeMdblistPercent:2189) | `bool forGuide = false` → `bool forGuide = true` | killed: C070 |
| `snapshot-mdblist-policy-content` (_currentEpisodeMdblistPercent:2191) | `_effectiveContentImdbId` → `null` | killed: C076 |
| `snapshot-mdblist-policy-mask` (_currentEpisodeMdblistPercent:2193) | `if (!forGuide && !policy.progressFrom(TrackingSource.mdblist)) return null;` → `` | killed: C070 |
| `snapshot-mdblist-guide-bypass` (_currentEpisodeMdblistPercent:2193) | `!forGuide && !policy.progressFrom` → `!policy.progressFrom` | killed: C072 |
| `snapshot-mdblist-identity` (_currentEpisodeMdblistPercent:2194) | `final imdbId = _currentSeriesImdbId;` → `final imdbId = 'tt5999999';` | killed: C079, C081, C077, C080, C078, C071, C075 |
| `snapshot-mdblist-null-id` (_currentEpisodeMdblistPercent:2195) | `if (imdbId == null) return null;` → `if (imdbId == null) throw StateError('snapshot identity');` | killed: C074 |
| `snapshot-mdblist-bind` (_currentEpisodeMdblistPercent:2196) | `_bindEpisodeTrackerProgressIdentity(imdbId);` → `` | killed: C079, C081, C077, C080, C078, C071, C075 |
| `snapshot-mdblist-cache` (_currentEpisodeMdblistPercent:2197) | `if (_mdblistEpisodeProgress == null)` → `if (true)` | killed: C071 |
| `snapshot-mdblist-guard` (_currentEpisodeMdblistPercent:2202) | `if (_episodeTrackerProgressImdbId != imdbId) return null;` → `` | killed: C081 |
| `snapshot-mdblist-late-guard` (_currentEpisodeMdblistPercent:2202) | `_episodeTrackerProgressImdbId != imdbId` → `_episodeTrackerProgressImdbId != _currentSeriesImdbId` | killed: C081 |
| `snapshot-mdblist-assign` (_currentEpisodeMdblistPercent:2203) | `_mdblistEpisodeProgress = loaded;` → `_mdblistEpisodeProgress = {};` | killed: C079, C081, C077, C080, C078, C071, C075 |
| `snapshot-mdblist-guide-mask` (_currentEpisodeMdblistPercent:2209) | `policy.guideProgressFrom(TrackingSource.mdblist, percent)` → `percent` | killed: C062 |
| `snapshot-mdblist-branch` (_currentEpisodeMdblistPercent:2208) | `return forGuide` → `return !forGuide` | killed: C062 |
| `snapshot-mdblist-se` (_currentEpisodeMdblistPercent:2205) | `_traktSeasonEpisode()` → `(season: 99, episode: 99)` | killed: C079, C081, C077, C080, C078, C071, C075 |
| `snapshot-mdblist-unresolved` (_currentEpisodeMdblistPercent:2206) | `if (se.season == null \|\| se.episode == null) return null;` → `if (se.season == null \|\| se.episode == null) throw StateError('snapshot coordinates');` | killed: C073 |
| `snapshot-mdblist-key` (_currentEpisodeMdblistPercent:2207) | `['${se.season}_${se.episode}']` → `['${se.episode}_${se.season}']` | killed: C077, C080, C078, C071, C075 |
| `log-initMdblistScrobble-0` (_initMdblistScrobble:2000) | `[MDBListDiag] player init requested=${widget.mdblistScrobble}` → `[ChangedMDB] player init requested=${widget.mdblistScrobble}` | killed: C023 |
| `log-initMdblistScrobble-1` (_initMdblistScrobble:2005) | `[MDBListDiag] player init skipped: tracking not requested` → `[ChangedMDB] player init skipped: tracking not requested` | killed: C023 |
| `log-initMdblistScrobble-2` (_initMdblistScrobble:2021) | `[MDBListDiag] player init skipped: player setup failed $e` → `[ChangedMDB] player init skipped: player setup failed $e` | killed: C015 |
| `log-initMdblistScrobble-3` (_initMdblistScrobble:2032) | `[MDBListDiag] player init skipped: invalid target metadata` → `[ChangedMDB] player init skipped: invalid target metadata` | killed: C027 |
| `log-initMdblistScrobble-4` (_initMdblistScrobble:2038) | `[MDBListDiag] player init abandoned: player unmounted` → `[ChangedMDB] player init abandoned: player unmounted` | killed: C002 |
| `log-initMdblistScrobble-5` (_initMdblistScrobble:2049) | `[MDBListDiag] player session ready imdb=${target.ids.imdb}` → `[ChangedMDB] player session ready imdb=${target.ids.imdb}` | killed: C052, C026, C004, C003 |
| `log-mdblistStop-0` (_mdblistStop:2081) | `[MDBListDiag] player stop complete=$complete` → `[ChangedMDB] player stop complete=$complete` | killed: C052 |
| `ref-01` (initState:1677) | `_initSimklScrobble();` → `` | killed: C091 |
| `ref-02` (initState:1678) | `_initMdblistScrobble();` → `` | killed: C061, C058 |
| `ref-03` (_resumeTrackingAfterValidationGate:2104) | `_simklScrobbleEnabled` → `true` | killed: C049, C048, C047, C050 |
| `ref-04` (_resumeTrackingAfterValidationGate:2107) | `_simklLastScrobbleAction = 'start';` → `` | killed: C142 |
| `ref-05` (_resumeTrackingAfterValidationGate:2108) | `_startSimklHeartbeat();` → `` | killed: C116 |
| `ref-06` (_resumeTrackingAfterValidationGate:2100) | `_updateMdblistPosition();` → `` | killed: C028 |
| `ref-07` (_resumeTrackingAfterValidationGate:2110) | `_mdblistPlay();` → `` | killed: C013 |
| `ref-08` (_bindEpisodeTrackerProgressIdentity:2130) | `_simklEpisodeProgress = null;` → `` | killed: C109, C037 |
| `ref-09` (_bindEpisodeTrackerProgressIdentity:2131) | `_mdblistEpisodeProgress = null;` → `` | killed: C077, C038 |
| `ref-10` (_bindPlayerInstanceSubscriptions:3413) | `_simklScrobbleEnabled` → `true` | killed: C095, C098, C093, C096, C099 |
| `ref-11` (_bindPlayerInstanceSubscriptions:3416) | `_simklLastScrobbleAction = 'start';` → `` | killed: C044, C045, C043 |
| `ref-12` (_bindPlayerInstanceSubscriptions:3422) | `_simklLastScrobbleAction` → `'stop'` | killed: C035, C036, C033, C034, C052, C085, C086, C087, C088 |
| `ref-13` (_bindPlayerInstanceSubscriptions:3423) | `_simklScrobble('pause');` → `` | killed: C035, C036, C033, C034, C052, C085, C086, C087, C088 |
| `ref-14` (_bindPlayerInstanceSubscriptions:3417) | `_startSimklHeartbeat();` → `` | killed: C035, C036, C033, C034, C087, C088, C114 |
| `ref-15` (_bindPlayerInstanceSubscriptions:3424) | `_stopSimklHeartbeat();` → `` | killed: C035, C087, C088 |
| `ref-16` (_bindPlayerInstanceSubscriptions:3332) | `_updateMdblistPosition();` → `` | killed: C035, C036, C033, C034, C087, C088 |
| `ref-17` (_bindPlayerInstanceSubscriptions:3371) | `_updateMdblistPosition();` → `` | killed: C022 |
| `ref-18` (_bindPlayerInstanceSubscriptions:3377) | `_mdblistPlay();` → `` | killed: C114 |
| `ref-19` (_bindPlayerInstanceSubscriptions:3427) | `_mdblistPlay();` → `` | killed: C035, C036, C033, C034, C087, C088 |
| `ref-20` (_bindPlayerInstanceSubscriptions:3432) | `_mdblistPause();` → `` | killed: C035, C036, C033, C034, C052, C085, C086, C087, C088 |
| `ref-21` (_onPlaybackEnded:4740) | `_simklScrobble('stop');` → `` | killed: C033 |
| `ref-22` (_onPlaybackEnded:4739) | `_stopSimklHeartbeat();` → `` | killed: C033 |
| `ref-23` (_onPlaybackEnded:4741) | `_mdblistStop(complete: true);` → `` | killed: C033 |
| `ref-24` (_switchToSourcePlaylist:9071) | `_switchMdblistTarget();` → `Future<void>.value();` | killed: C009 |
| `ref-25` (_loadPlaylistIndex:10041) | `_switchMdblistTarget();` → `Future<void>.value();` | killed: C009 |
| `ref-26` (_loadPlaylistIndexAttempt:10145) | `_simklScrobble('stop');` → `` | killed: C137 |
| `ref-27` (_loadPlaylistIndexAttempt:10144) | `_stopSimklHeartbeat();` → `` | killed: C137 |
| `ref-28` (_loadPlaylistIndexAttempt:10149) | `_updateMdblistPosition();` → `` | killed: C021 |
| `ref-29` (_loadPlaylistIndexAttempt:10164) | `_switchMdblistTarget();` → `Future<void>.value();` | killed: C008 |
| `ref-30` (_onPipAction:11260) | `_simklScrobbleSeek(position);` → `` | device_pending: Installed only behind sealed Android/iOS predicates; no raw Platform seam. Human PiP seek checklist. |
| `ref-31` (_onPipAction:11261) | `_mdblistScrobbleSeek(position);` → `` | device_pending: Installed only behind sealed Android/iOS predicates; no raw Platform seam. Human PiP seek checklist. |
| `ref-32` (dispose:11455) | `_simklScrobble('stop');` → `` | killed: C034, C085, C086 |
| `ref-33` (dispose:11454) | `_stopSimklHeartbeat();` → `` | killed: C034, C046 |
| `ref-34` (dispose:11457) | `_mdblistSession?.close()` → `Future<void>.value()` | killed: C046, C005 |
| `ref-35` (dispose:11456) | `_mdblistStop();` → `` | killed: C016 |
| `ref-36` (_maybeRestoreResume:11728) | `_launchSimklPercentSpent` → `true` | killed: C101 |
| `ref-37` (_maybeRestoreResume:11729) | `_launchSimklPercentSpent = true;` → `` | killed: C101 |
| `ref-38` (_maybeRestoreResume:11779) | `_currentEpisodeSimklPercent()` → `Future<double?>.value(null)` | killed: C101, C106 |
| `ref-39` (_maybeRestoreResume:11856) | `_currentEpisodeSimklPercent(forGuide: true)` → `Future<double?>.value(null)` | killed: C102 |
| `ref-40` (_maybeRestoreResume:11730) | `_launchMdblistPercentSpent` → `true` | killed: C071 |
| `ref-41` (_maybeRestoreResume:11731) | `_launchMdblistPercentSpent = true;` → `` | killed: C071 |
| `ref-42` (_maybeRestoreResume:11764) | `_currentEpisodeMdblistPercent()` → `Future<double?>.value(null)` | killed: C071, C075 |
| `ref-43` (_maybeRestoreResume:11857) | `_currentEpisodeMdblistPercent(         forGuide: true,       )` → `Future<double?>.value(null)` | killed: C072 |
| `ref-44` (_tvScrubCommit:12539) | `_simklScrobbleSeek(target);` → `` | killed: C032 |
| `ref-45` (_tvScrubCommit:12540) | `_mdblistScrobbleSeek(target);` → `` | killed: C032 |
| `ref-46` (_buildTvControls:12608) | `_simklScrobbleSeek(target);` → `` | killed: C031 |
| `ref-47` (_buildTvControls:12609) | `_mdblistScrobbleSeek(target);` → `` | killed: C031 |
| `ref-48` (_handleDoubleTap:13096) | `_simklScrobbleSeek(clamped);` → `` | killed: C040, C041 |
| `ref-49` (_handleDoubleTap:13097) | `_mdblistScrobbleSeek(clamped);` → `` | killed: C040, C041 |
| `ref-50` (_onPanEnd:13194) | `_simklScrobbleSeek(target);` → `` | killed: C053 |
| `ref-51` (_onPanEnd:13195) | `_mdblistScrobbleSeek(target);` → `` | killed: C053 |
| `ref-52` (build:14178) | `_simklScrobbleSeek(newPos);` → `` | killed: C055 |
| `ref-53` (build:14192) | `_simklScrobbleSeek(newPos);` → `` | killed: C054 |
| `ref-54` (build:14730) | `_simklScrobbleSeek(settledPosition);` → `` | killed: C088, C057, C055 |
| `ref-55` (build:14179) | `_mdblistScrobbleSeek(newPos);` → `` | killed: C055 |
| `ref-56` (build:14193) | `_mdblistScrobbleSeek(newPos);` → `` | killed: C054 |
| `ref-57` (build:14731) | `_mdblistScrobbleSeek(settledPosition);` → `` | killed: C087, C088, C055 |
| `ref-58` (_VpSkipSegmentHostAdapter:17301) | `_simklScrobbleSeek` → `_trakt.traktScrobbleSeek` | killed: skip publishes clock before seek, queues tracking before haptic and preserves remote stop order, skip tracker seek order arms Trakt heartbeat before Simkl |
| `ref-59` (_VpSkipSegmentHostAdapter:17303) | `_mdblistScrobbleSeek` → `_trakt.traktScrobbleSeek` | killed: skip publishes clock before seek, queues tracking before haptic and preserves remote stop order, skip tracker seek order arms Trakt heartbeat before Simkl |
| `ast-048` (_simklScrobble:1842) | `return;` → `throw StateError('vp return mutation');` | killed: C134 |
| `ast-073` (_simklScrobble:1861) | `'pause'` → `'other'` | killed: C085, C086, C083, C044, C045, C043 |
| `ast-077` (_simklScrobble:1869) | `'stop'` → `'other'` | killed: C085, C086, C084 |
| `ast-088` (_startSimklHeartbeat:1893) | `return;` → `throw StateError('vp return mutation');` | killed: C125 |
| `ast-093` (_startSimklHeartbeat:1895) | `return;` → `throw StateError('vp return mutation');` | killed: C124 |
| `ast-109` (_startSimklHeartbeat:1909) | `% (>80%)'` → `% (>80%)x'` | killed: C122 |
| `ast-111` (_startSimklHeartbeat:1912) | `return;` → `throw StateError('vp return mutation');` | killed: C122 |
| `ast-118` (_startSimklHeartbeat:1928) | `1` → `2` | killed: C122 |
| `ast-119` (_startSimklHeartbeat:1928) | `%'` → `%x'` | killed: C122 |
| `ast-129` (_simklScrobbleSeek:1947) | `return;` → `throw StateError('vp return mutation');` | killed: C135 |
| `ast-134` (_simklScrobbleSeek:1948) | `return;` → `throw StateError('vp return mutation');` | killed: C140, C139 |
| `ast-174` (_mdblistTarget:1986) | `return MdblistScrobbleTarget.movie(ids);` → `return MdblistScrobbleTarget.episode(ids, season: 99, episode: 99);` | killed: C086 |
| `ast-193` (_initMdblistScrobble:2000) | `'[MDBListDiag] player init requested=` → `'[MDBListDiag] player init requested=x` | killed: C023 |
| `ast-194` (_initMdblistScrobble:2000) | `'` → `x'` | killed: C023 |
| `ast-195` (_initMdblistScrobble:2001) | `'flag=$kMdblistEnabled imdb=${widget.contentImdbId} '` → `'changed diagnostic'` | killed: C023 |
| `ast-199` (_initMdblistScrobble:2002) | `'type=${widget.contentType}'` → `'changed diagnostic'` | killed: C023 |
| `ast-206` (_initMdblistScrobble:2006) | `return;` → `throw StateError('vp return mutation');` | killed: C065 |
| `ast-218` (_initMdblistScrobble:2024) | `return;` → `throw StateError('vp return mutation');` | killed: C025 |
| `ast-225` (_initMdblistScrobble:2033) | `return;` → `throw StateError('vp return mutation');` | killed: C066, C069, C067, C064 |
| `ast-230` (_initMdblistScrobble:2039) | `return;` → `throw StateError('vp return mutation');` | killed: C002 |
| `ast-237` (_initMdblistScrobble:2049) | `'[MDBListDiag] player session ready imdb=` → `'[MDBListDiag] player session ready imdb=x` | killed: C052, C026, C004, C003 |
| `ast-238` (_initMdblistScrobble:2049) | `'` → `x'` | killed: C052, C026, C004, C003 |
| `ast-239` (_initMdblistScrobble:2050) | `'episode=${target.isEpisode} playing=$_isPlaying '` → `'changed diagnostic'` | killed: C052, C026, C004, C003 |
| `ast-243` (_initMdblistScrobble:2051) | `'positionMs=${_position.inMilliseconds} '` → `'changed diagnostic'` | killed: C052, C026, C004, C003 |
| `ast-246` (_initMdblistScrobble:2052) | `'durationMs=${_duration.inMilliseconds}'` → `'changed diagnostic'` | killed: C052, C026, C004, C003 |
| `ast-272` (_mdblistStop:2081) | `'[MDBListDiag] player stop complete=` → `'[MDBListDiag] player stop complete=x` | killed: C052 |
| `ast-273` (_mdblistStop:2081) | `'` → `x'` | killed: C052 |
| `ast-274` (_mdblistStop:2082) | `'session=${_mdblistSession != null} '` → `'changed diagnostic'` | killed: C082 |
| `ast-279` (_mdblistStop:2083) | `'positionMs=${_position.inMilliseconds} '` → `'changed diagnostic'` | killed: C052 |
| `ast-282` (_mdblistStop:2084) | `'durationMs=${_duration.inMilliseconds}'` → `'changed diagnostic'` | killed: C052 |
| `ast-298` (_switchMdblistTarget:2118) | `return;` → `throw StateError('vp return mutation');` | killed: C007 |
| `ast-316` (_currentEpisodeSimklPercent:2149) | `final loaded =           await TrackerEpisodeProgressStorage.getEpisodeSimklProgress(         …` → `final loaded = <String, double>{};` | killed: C111, C113, C109, C112, C110, C101, C106 |
| `ast-322` (_currentEpisodeSimklPercent:2157) | `int? season;` → `int? season = 99;` | equivalent: The series-playlist and single-file series branches assign both season and episode. On other paths the unchanged episode remains null and the joint guard rejects; changing only season initializer to 99 cannot reach a lookup. |
| `ast-323` (_currentEpisodeSimklPercent:2158) | `int? episode;` → `int? episode = 99;` | equivalent: The series-playlist and single-file series branches assign both season and episode. On other paths the unchanged season remains null and the joint guard rejects; changing only episode initializer to 99 cannot reach a lookup. |
| `ast-324` (_currentEpisodeSimklPercent:2159) | `final seriesPlaylist = _seriesPlaylist;` → `final seriesPlaylist = null as SeriesPlaylist?;` | killed: C111, C113, C109, C112, C110, C101 |
| `ast-329` (_currentEpisodeSimklPercent:2161) | `final playlist = _activePlaylist;` → `final playlist = null as List<PlaylistEntry>?;` | killed: C111, C113, C109, C112, C110, C101 |
| `ast-333` (_currentEpisodeSimklPercent:2162) | `if (seriesPlaylist != null && seriesPlaylist.isSeries) {       final playlist = _activePlaylis…` → `if (seriesPlaylist != null && seriesPlaylist.isSeries) {       final playlist = _activePlaylis…` | killed: C108 |
| `ast-389` (_currentEpisodeMdblistPercent:2198) | `final loaded =           await TrackerEpisodeProgressStorage.getEpisodeMdblistProgress(       …` → `final loaded = <String, double>{};` | killed: C079, C081, C077, C080, C078, C071, C075 |
| `caller-init-mounted` (_initializePlayer:2879) | `if (!mounted) return;` → `` | killed: C039 |

## Phase 6 Step 0b — independent sample and survivor audit (2026-10-12)

Claude sampled application original `6d2ac75d8` (byte-identical to `ea7901ead`):
**18/20 assertion kills (90%)**, no compile-error credit. Raw sample evidence is
`p6/claude-sample/{p6-claude-muts.json,p6-claude-run.log,results.json}`. Both
survivors match existing Step-0 equivalence entries, not newly accepted gaps.
The exact mutations were replayed against detached `6d2ac75d8` with focused
public-caller tests. Those tests pass on the original and both exact survivors;
two neighboring non-equivalent mutations assertion-fail. No artificial private
State writes, second initialization or forged resolver record is credited.

| Sample | Observed result | Original witness / closure |
|---|---|---|
| `i1` | killed | Assertion kill: Secondary simkl custom identity policy disables otherwise enabled tracking before authentication, Simkl initially disabled policy cannot install even a silent heartbeat before any input |
| `i2` | survived | Survives; equivalent to `simkl-init-marker`; new authentication-mid-playback pause/exit case passes unchanged; `i2-marker-pause-negative` assertion-kills |
| `i3` | survived | Survives; equivalent to `simkl-unresolved-episode`; new incomplete season-only launch case rejects pause/heartbeat/seek/EOF/dispose; `i3-whole-guard-negative` assertion-kills |
| `i4` | killed | Assertion kill: Secondary pause at 80 preserves Simkl strict and MDBList inclusive completion thresholds, Secondary simkl suspended snapshot episode pins late coordinates and original identity guard |
| `i5` | killed | Assertion kill: Simkl EOF then disposal deduplicates the already sent stop checkpoint, Simkl held 201 stop across dispose pins response revisions and service-owned recovery |
| `i6` | killed | Assertion kill: Secondary all-tracker pause fanout preserves ordered timer ownership and tracker-specific payloads, Secondary seek at 80 crosses tracker thresholds and seeking back rearms checkpoints |
| `i7` | killed | Assertion kill: Secondary all-tracker pause fanout preserves ordered timer ownership and tracker-specific payloads, Secondary all-tracker seek fanout preserves ordered timer ownership and tracker-specific payloads |
| `i8` | killed | Assertion kill: Simkl public seek endpoints send exactly one hundred then zero and a reverse seek at eighty remains resumable |
| `i9` | killed | Assertion kill: Secondary seek at 80 crosses tracker thresholds and seeking back rearms checkpoints, Secondary seek at 81 crosses tracker thresholds and seeking back rearms checkpoints |
| `i10` | killed | Assertion kill: Simkl public seek endpoints send exactly one hundred then zero and a reverse seek at eighty remains resumable, skip tracker seek order arms Trakt heartbeat before Simkl |
| `i11` | killed | Assertion kill: Secondary mdblist initialization type gate preserves absent checkpoints |
| `i12` | killed | Assertion kill: Secondary mdblist custom identity policy disables otherwise enabled tracking before authentication, Secondary mdblist initialization target gate preserves absent checkpoints |
| `i13` | killed | Assertion kill: MDBList startup policy precedes suspended player setup and none preserves the captured setting, MDBList startup policy precedes suspended player setup and dispose preserves the captured setting |
| `i14` | killed | Assertion kill: MDBList startup policy precedes suspended player setup and none preserves the captured setting, MDBList captured target before capability widget completion retains original allocation and guards |
| `i15` | killed | Assertion kill: MDBList capability finishing paused allocates without starting until the real playing edge |
| `i16` | killed | Assertion kill: Secondary held resume pins MDBList raw initialization then persistable pause and stop diagnostics, MDBList held resume play samples its promised position before any intervening native position event |
| `i17` | killed | Assertion kill: Secondary all-tracker EOF fanout preserves ordered timer ownership and tracker-specific payloads |
| `i18` | killed | Assertion kill: MDBList live seek and duration edge during manual validation keeps its original checkpoint at early-close |
| `i19` | killed | Assertion kill: MDBList episode selection with newly invalid live identity exits then continues its outgoing target |
| `i20` | killed | Assertion kill: Secondary held resume pins MDBList raw initialization then persistable pause and stop diagnostics |

**i2 proof.** `_initSimklScrobble` has one original caller, `initState` (1677).
Enablement remains false until its awaited policy/auth result is assigned; all
pause/stop/seek writers reject false enablement. Between that assignment and
the initializer's start stamp there is no await, callback or effectful getter.
The marker is therefore null or already start; both differ from every live
pause/stop action. No live caller passes start to `_simklScrobble`. The first
pause/stop writes its own action, and timer/playing/validation callers overwrite
the marker independently. Removing only the init stamp cannot suppress the
first pause. Changing it to pause does suppress that pause and assertion-fails
the new test. The original stamp remains verbatim in production.

**i3 proof.** `_traktSeasonEpisode` accepts playlist and launch coordinates only
when both are non-null (1758–1781). Its last fallback uses `parseFilename`.
All paired regex groups are bounded decimal digits (1–2 season / 1–3 episode),
so both parse; one-group episode patterns parse a bounded episode before any
season inference. Anime sets season only after parsing an episode, and special
content sets both together. No later parser assignment removes an episode.
Thus the season-only launch input falls back to (null, null); episode-only
filenames can produce (null, episode), but (season, null) is unreachable from
original callers. Removing the episode operand is equivalent. A direct forged
record/private-call test would violate original-caller characterization and is
not used. The original two-operand guard remains verbatim in production.

| New caller case | Original control | Exact survivor | Assertion-failing negative |
|---|---|---|---|
| Authentication arrives while already playing with positive duration; no later playing edge; user pause sends 25%, cancels timer, disposal sends stop 25% | PASS | `i2` PASS | `i2-marker-pause-negative` killed |
| Season-only launch without an episode; pause, heartbeat, seek above 80%, EOF and disposal send no Simkl request | PASS | `i3` PASS | `i3-whole-guard-negative` killed |

Evidence: `p6/step0b/closure-results.json` records the commands, test hashes,
completed names and assertion messages; per-mutation patches and logs remain.
The broader original control passes **146 cases** (144 new P6 cases plus two
existing skip integrations). Existing 320-point Step-0 classifications stay
301 killed / 15 equivalent / two dormant / two device-pending; the new cases
have two additional non-equivalent assertion witnesses, without relabeling the
exact survivor replays as kills. The observed independent score stays 18/20.

One evidence-path error is explicit: the first addendum control reused Step 0's
raw `mutations/control.jsonl` path. Its accepted ledger was restored byte-for-byte,
and all mutation logs/full-suite baselines remain intact; the old raw control
is superseded by `step0b/full-control.jsonl` (146 passing cases), not reconstructed.
`step0b/evidence-path-note.json` and `step0/accepted-raw-control-superseded.json`
record the old expected hash and actual replacement. No outcome was allowlisted.
The new suite baseline and resulting revision are recorded in Step-0b completion
once the additions-only comparison is complete. Application/pubspec unchanged.

Step-0b full suite: **13,193 success / 13 pre-existing failure / 28 pre-existing
load error / 20 skip**; official comparator and strict old-identity/outcome
comparison PASS, exactly two passing additions, zero missing/changed/skipped old
identities. New test analyzer/format pass. The application remains byte-identical
to the named original; no manifest or CI transition in this addendum.

## Phase 6 Step 1 — production creation (2026-10-12)

Follows Step-0b `8c5a962c3`; original application `ea7901ead`. Only the three
manifest-owned application paths change: the facade and the Simkl/MDBList
controllers. All 24 original declarations move, all 59 retained references
(57 substitutions plus two counted skip-adapter rewrites) retain their statement
positions, and all 14 earlier destinations remain protected. Current-tree
comparison passes with zero differences, including the resumed verification.
Both controllers exactly match Step T's reviewed formatted materialization.

| Responsibility / path | Production ownership |
|---|---|
| `presentation/legacy_video_player/vp_simkl_scrobbler.dart` | `VpSimklScrobbler` + 19-member Host; 283 lines; five fields / seven methods |
| `presentation/legacy_video_player/vp_mdblist_scrobbler.dart` | `VpMdblistScrobbler` + 15-member Host; 187 lines; three fields / nine methods |
| State constructor / adapters | Eager inert `_simkl` then `_mdblist` after `_trakt`; computed, frozen live getters; no constructor Host read or scheduling |
| Shared Trakt progress / skip adapter | Two full `_trakt.traktProgress` chains become `_host.traktProgress`, forwarded by the facade; patched whole skip adapter carries P5's Trakt forwarder and two new counted rewrites; no sibling import |
| Lifecycle / MDBList initialization | Original fan-out and each disposal statement stay in place; session close remains unawaited at its original position; policy → player-init await/catch → mounted → captured target → capability await → mounted → allocation/raw update/assignment/conditional play is unchanged |
| Facade size | 17,394 → 17,087; `--update` shrink retained and dated P6 note appended with all previous notes preserved |

`vplayer_p6.json` is applied. CI current/self-test and scoped analyzer switch to
P6; P1–P5 `--at` remain `31a347ad2` / `fc24e32ae` / `890df14d8` / `315028407` /
`ea7901ead`, checkout remains fetch-depth 0. The existing recursive `lib/features`
format/analyze scope includes both new files and the explicit facade stays covered.
The frozen P6 analyzer inventory already recorded at Step T preserves every
previous mapping/maximum; it is not enlarged. Five exact retained-import warnings
from that probe receive their allowlist entries. No import cleanup or suppression.
All 22 P6 characterization files (144 added behavior cases) are registered once
in `ci_behavior_tests.txt`; the test-hook define remains enabled. Both destinations
are added to the theme manifest, route boundaries and all three frozen-path lists.

Source guard retarget: `android_tv_mdblist_progress_source_test.dart` still uses
the validating, chaining reader for all three original percentage declarations;
Simkl/MDBList expected prefixes become `_host.`. Identity capture/rejection,
carried TVMaze identity, metadata readiness and rewatch assertions remain.
Each new adapter additionally has its own class-local live identity/binder
assertions. In a detached evidence-only materialization the moved control passes;
changing only Simkl's or only MDBList's computed current-series getter to the
widget id independently assertion-fails. Complete patches/logs are in
`p6/step1/source-guard/`; the original worktree is restored afterward.

Creation checks: **167 focused tests pass** (all P6 behaviors, existing skip
integrations, Android TV source guards and theme guards); root analyzer comparator
passes **94 scoped occurrences, zero additions**, infos/multiplicities included;
format idempotent, size **3,000 files / 140 ratchets**, architecture **1,668 migrated
files** and real architecture negatives pass. The production application is the
exact Step-T formatted split: its two optional commas, idempotence and zero
formatting diagnostic delta are archived there. No new seam, bug fix, pubspec
change, real network, device command or failure allowance. i2/i3 remain verbatim,
with their exact survivor replays/source equivalences recorded in Step 0b.
Clean-tree full-suite/history/self-test/analyzer/format/architecture/build gate
follows separately; manual Simkl/MDBList movie/series and PiP checks remain pending.
Resulting revision and source/check hashes are recorded in `p6/step1/completion.json`.


## Phase 6 gate fixture scheduling closure (2026-10-12)

The first clean creation gate at `dd6fa4016` is incomplete and excluded: a
pending MDBList profile-handoff test hung, then later cases inherited the blocked
`runAsync`. The original application's isolated pair passed twice and reached an
external 120-second deadline once. This is recorded as an original fixture
scheduling flake, without a failure allowance, in `p6/gate/fixture-note/NOTE.json`.
The fixture now pumps while awaiting the same public registry operations and
incoming synthetic-token write, following Phase 5's `finish()` precedent. It
preserves all 21 expectation calls, eight identities and HTTP response holds.
Original and moved complete eight-case controls pass three times each (48 passes).
The original production source is restored after the independent witnesses.

| Original mutation on stabilized fixture | Result |
|---|---|
| `md-target-season`: change captured season to 99 | assertion-killed |
| `md-switch-await`: remove target-switch await | assertion-killed |
| `ref-34`: suppress disposal session close | assertion-killed |
| `simkl-seek-api-0-progress`: send zero stop progress | assertion-killed |
| `ref-28`, `simkl-seek-stop-heartbeat`, `md-init-session-capability` | survive this eight-case subset; broader original Step-0 witnesses remain unchanged; no supplemental kill claimed |

These are supplemental fixture proofs, not additions to the original 320-point
sweep or a changed independent-sample score. Full-suite Step-0b identities and
outcomes remain the comparison baseline. No application, pubspec, assertion or
expected-outcome change; fresh clean-tree gate follows. Logs, patches, replay
results and fixture/revision hashes live under `p6/gate/fixture-note/`.


## Phase 6 clean-tree gate (2026-10-12)

Clean tested revision `5bb287d72` follows creation `dd6fa4016` and the test-only
fixture closure. Production and checker/CI inputs are byte-identical to creation;
complete creation-input check runs are reused with the archived equality audit.
The fixture's original/moved repeated controls and mutation witnesses validate
its changed scheduling against the same Step-0b identity baseline.

| Gate | Archived result |
|---|---|
| Full suite; `nice -n 19 suite_evidence.py run ... --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true` | 13,193 success / 13 failure / 28 load error / 20 skip; exact baseline identity/outcome equality and official comparator PASS; zero added/missing/changed/newly skipped |
| All Dart manifest self-tests, P6 self/current/at-creation, P1–P5 historical, Kotlin self-test | All 35 commands PASS; Kotlin 597 tests; current protection includes all 14 earlier destinations |
| Analyzer, root and strict feature CI scope | 94 scoped occurrences / zero additions; infos, declaration identities and multiplicity preserved; comparator negatives and global allowlist PASS |
| Format / size / architecture | Idempotent CI format; changed test format/analyzer PASS; 3,000 files / 140 ratchets; 1,668 migrated files and architecture negatives PASS; post-fixture current/size/architecture PASS |
| Isolated parser audit | Every manifest invocation selects a fresh package under ignored `.dart_tool/vplayer_parser/`; copied kernels deleted; nested routing archived |
| APK release, then macOS release; `nice -n 19 flutter build <target> --release --no-pub` | Both PASS on clean tested revision; APK, macOS executable and AOT hashes archived; existing macOS plugin SwiftPM notices remain warnings |

Evidence is exclusively `refactor-evidence/vplayer/p6/gate/` in the git common
directory: complete `suite-rerun.jsonl`/environment, strict delta, official
comparison, fast/manifest logs, parser audit, build logs/results, creation-input
reuse audit and `completion.json`. The first interrupted suite remains archived
as incomplete and excluded. No changed expected outcome or failure allowance.
Flutter 3.44.8 / Dart 3.12.2, pubspec and all frozen application hashes remain
unchanged. The manual Simkl/MDBList movie/series threshold, resume, disabled and
mid-session-disable checks plus earlier device/PiP items remain pending. Existing
profile/cache/recovery gaps stay Follow-ups; no bug fixes or later moves.


## Phase 7 Step T — local completion tooling (2026-10-13)

The named original is `2defa5100` (facade 17,087 lines), following approved
`7498196ca`. Re-measurement is archived in `p7/tooling/inventory.json` and
`probe/remeasured.json`: 828 exhaustive declarations, 14 moved, 813 retained,
one patched State constructor and exactly 11 retained references at their
original statement positions. Six fields are inert: four false literals and
two references to `LocalCompletionStorage.defaultLocalCompletionThreshold`,
which is `static const int` 80. Per-field source/line proofs are archived.

The draft complete manifest freezes 21 live Host getters, the adapter and the
eager `_completion` assignment after `_mdblist`. All 16 earlier destinations
are protected. No sibling patch or shared guard change is needed. Raw and
formatted complete evidence materializations compare with zero differences;
optional comma insertion/deletion is zero, formatting idempotent, introduced
formatting diagnostics zero. Real P7 positives, ten body/constructor/selector/
retained negatives and independent binding-only registration/capture negatives
pass. Every previous Dart configuration retains its behavior.

All 34 required tooling commands pass: 26 existing Dart manifest self-tests,
P7 universal/self-original (all 828 declarations), historical P1–P6 at
`31a347ad2` / `fc24e32ae` / `890df14d8` / `315028407` / `ea7901ead` /
`2defa5100`, plus Kotlin (597 tests). Root/strict/raw/formatted analyzer probes
record 94/165/98/98 scoped diagnostics; earlier mappings and maxima retained.
The episode marker's `empty_catches` identity and multiplicity one are preserved,
not merely a total count. Async-context identities are unchanged; comparator
negatives pass. Size 3,000 files / 140 ratchets and architecture 1,668 pass.
Tool-only packages are isolated under ignored `.dart_tool/vplayer_parser/`,
with copied kernels deleted and routing recorded under P7 evidence.

A driver inventory-seed typo was rejected before analyzer execution, archived,
and corrected to P6. The original full-suite baseline is reused from the P6
clean gate after exact application/pubspec/analysis configuration equality with
`2defa5100`, using the same Flutter/Dart SDK. No new failures accepted. Manifest
stays draft, application/pubspec unchanged and production destination absent.
CI current/self/analyzer transition and test/theme registration wait for the
Step-1 commit creating `vp_local_completion.dart`. Step 0 remains separate.

## Phase 7 Step 0 — original local completion characterization (2026-10-13)

Application original `2defa5100`; tooling checkpoint `98bf408f4`. Controls and
mutations use the detached `p7/step0/original/` worktree. The main application,
pubspec, CI/theme/source-guard registrations and size baseline stay unchanged;
`vplayer_p7.json` remains a draft and `vp_local_completion.dart` is absent.

The Phase 5–6 synthetic HTTP transport, credential seeding, profile-policy mirror
and pumping `finish()` helper are reused. A new test-only await-delivery observer
holds actual storage results at executed callers. Its completion-loader barrier
accepts only the two-element `List<int>`, so player defaults and construction can
finish independently. Physical preferences use the real preference transport;
profile-specific resume rows are inspected in each actual SQLite database.
The fake frame-position opt-in preserves its previous 80 ms default.

Coverage pins thresholds and both loader arrival orders, all sixteen policy
combinations, native identities and channel exclusions, live widget selectors,
movie completion/rewatch, single-file and parsed playlists, validation/zero
position/zero duration, caller resets and legacy resume/speed restoration. All
six moved initializers have early-window witnesses, including both directions
of the default-80 threshold mutation. EOF is independently covered: episodes
ignore local enablement and the position one-shot, whereas movies keep their
tracking/identity/one-shot gates. Repeated and overlapping EOF writes pin stamps
and revisions; all three tracker stops precede awaited episode/movie work and
the sleep-stop decision. Physical resume cleanup also pins playback-sync rather
than ordinary library notification, including a later EOF with a fresh bookmark.

The cross-profile cases hold A's real read, finish the public B handoff, then
release while mounted or disposed. They assert both profiles' physical contents,
A's unrelated records copied into B, B's unrelated records lost, notifications,
cleanup and Continue Watching. Scoped resume removal separately deletes A's row
and preserves B's row. These pre-existing writes remain unchanged. Caught movie
and episode failures spend their guards; rejected preference writes can update
the cache while physical contents remain old. SQL and preference failures pin
partial `Future.wait` cleanup. The unawaited rewatch failure remains uncaught;
a held unmark can remove a later completed marker without restoring resume saves.

Two additional original windows are preserved in the plan's Follow-ups. A first
movie jump above default 80 can be unmarked when 90 arrives if the rewatch flag
was never spent; ordinary earlier low progress preserves its marker. A source
replacement publishes its rebuilt cache before URL resolution and reset: an
outgoing index that still fits can mark an unplayed incoming episode, while an
out-of-range index spends the episode guard without writing. The missing-title
return is therefore **not equivalent**: its absence spends the old guard and
suppresses that later incoming write. Both source cases use public guide selection,
a held synthetic TorBox response and `finish()`, without private State access.

The statement/branch/literal inventory covers all 14 moved declarations and the
frozen 11 retained occurrences. `ast-site-matrix.json` maps every one of 189
original analyzer AST sites to concrete mutations. All six initializers have
eight probes, including both threshold directions. The first 113-point sweep
recorded 97 assertion kills, 15 survivors and one nullable-promotion compilation
failure. The latter receives no kill credit and is replaced by a null-safe
conjunction at the same fallback branch. Real gaps and omitted name selectors
are closed with original caller tests and separate replay records. Three
invariances have source proofs and passing final-input replays: removing either
playlist coordinate null check throws inside the same empty catch before any
service call, after the guard was spent; removing the outer movie one-shot still
hits the synchronous identical check in its callee before any side effect.
The extra retained resume-result mutation pins the unfinished restore path.

Rejected development attempts stay archived. The copied first runner selected
`ea7901ead` instead of the named P7 base; that control and its preflight-rejected
sweep are excluded. The corrected runner verifies the application SHA against
`git show 2defa5100` before every invocation and restores it after every mutation.
Expanded-control fixture assumptions (cache versus physical write failure,
auto-resume overriding a requested index, and a stale preference instance during
cache refill) are corrected in separate final logs. Refilling the current cache
then kills removal of the failed-rewatch guard directly. No error-only,
load-failing, compilation-failing, timed-out or incomplete run is counted as
an assertion kill.

The final canonical sweep has **114 assertion-killed points and three evidenced
equivalences (117 total)**, including four supplemental witnesses. All **98 new
behavior identities** have an assertion-failing original witness with their final
case-file and support-file hashes. The per-case table and `coverage.json` record
the exact run, not just a suite failure count. No source-text test receives
behavior coverage credit.

### New characterization files

| File under `test/features/video_player/` | Cases |
|---|---|
| `video_player_completion_basic_test.dart` | 11 |
| `video_player_completion_checkpoint_test.dart` | 1 |
| `video_player_completion_eof_test.dart` | 10 |
| `video_player_completion_failures_test.dart` | 6 |
| `video_player_completion_inputs_test.dart` | 12 |
| `video_player_completion_loads_test.dart` | 31 |
| `video_player_completion_playlist_boundaries_test.dart` | 3 |
| `video_player_completion_playlist_test.dart` | 9 |
| `video_player_completion_profiles_test.dart` | 6 |
| `video_player_completion_resets_test.dart` | 5 |
| `video_player_completion_resume_test.dart` | 2 |
| `video_player_completion_source_window_test.dart` | 2 |

### Declaration and retained-reference coverage

| Original declaration (State owner) | Original caller / observable coverage | Points |
|---|---|---|
| `_currentEpisodeMarkedAsFinished` | Early first completion, position one-shot, repeated/overlapping EOF, incomplete metadata and all caller resets | 1 |
| `_currentMovieMarkedAsFinished` | Early first completion, cleanup once, caught failures, external bookmark preservation and direct EOF | 1 |
| `_currentMovieRewatchStarted` | Initial low progress, exact first-threshold input, public marker refill after failed unmark and all resets | 1 |
| `_movieCompletionThreshold` | Default 80 before selective delivery; 70/90 initializer probes, 50/70/80/100 configured equality and both arrival orders | 2 |
| `_episodeCompletionThreshold` | Default 80 before selective delivery; 70/90 initializer probes, asymmetric settings and paused re-evaluation | 2 |
| `_loadLocalCompletionThresholds` | Actual independent reads/indexes/writes, lower/higher delivery without another tick, uncaught malformed storage and disposal | 8 |
| `_usesLocalCompletionTracking` | Sixteen configurations, native/media-library ownership, channel exclusions and public flag retirement | 8 |
| `_forceLocalCompletionTracking` | Policy held before delivery with tracker intent, native identities, sixteen settings/flag combinations and live selectors | 1 |
| `_loadTrackingPolicy` | Content identity, all three live flags, independent arrival orders, immediate re-evaluation and disposal | 8 |
| `_currentLocalMovieImdbId` | Non-movie/null/empty/space/trim identity; mark/unmark physical contents and finished/unfinished resume decisions | 5 |
| `_resetLocalCompletionState` | MagicTV, Stremio TV and playlist callbacks; rewatch and incoming completion on the existing State | 3 |
| `_markCurrentEpisodeAsFinished` | Single-file title/coordinates/ID; parsed/enriched/fallback playlist; missing metadata, old-index window, repeated/overlapping/tracker EOF, catches and cross-profile physical writes | 31 |
| `_markCurrentMovieAsFinished` | Tracking/identity/one-shot gates, marker/CW/map/scoped-resume cleanup, playback-sync notification and partial/caught failures | 10 |
| `_checkAndApplyLocalCompletion` | Validation, zero position/duration, percent arithmetic and equality, rewatch/held failure, both series suppliers and position-only one-shot | 24 |

| Frozen reference | Original containing declaration | Original line / read or call | Witness |
|---|---|---|---|
| `ref-00` | `initState` | 1630: `_loadLocalCompletionThresholds()` | `final2-ref-00` |
| `ref-01` | `initState` | 1628: `_loadTrackingPolicy()` | `ref-01` |
| `ref-02` | `_bindPlayerInstanceSubscriptions` | 2940: `_checkAndApplyLocalCompletion()` | `ref-02` |
| `ref-03` | `_onPlaybackEnded` | 4348: `_markCurrentEpisodeAsFinished()` | `witness-ref-03` |
| `ref-04` | `_onPlaybackEnded` | 4352: `_markCurrentMovieAsFinished()` | `witness-ref-04` |
| `ref-05` | `_goToNextEpisode` | 5237: `_resetLocalCompletionState()` | `ref-05` |
| `ref-06` | `_switchToStremioTvChannel` | 9030: `_resetLocalCompletionState()` | `ref-06` |
| `ref-07` | `_loadPlaylistIndexAttempt` | 9770: `_resetLocalCompletionState()` | `ref-07` |
| `ref-08` | `_maybeRestoreResume` | 11404: `_currentLocalMovieImdbId` | `ref-08` |
| `ref-09` | `_saveResumeLocked` | 11848: `_currentMovieMarkedAsFinished` | `ref-09` |
| `ref-10` | `_saveResumeLocked` | 11848: `_currentLocalMovieImdbId` | `ref-10` |

The 11-occurrence ledger remains unchanged. Supplemental mutations cover the
whole tracking predicate in both directions, the transient upper-index guard and
the retained finished-movie resume decision; they introduce no production edit.

### Canonical original mutation table

| Point | Declaration / original line | Mutation (complete patch in evidence) | Result / recorded run |
|---|---|---|---|
| `field-currentEpisodeMarkedAsFinished` | `_currentEpisodeMarkedAsFinished`:1392 | `false` → `true` | KILL, 8 assertions; `field-currentEpisodeMarkedAsFinished` |
| `field-currentMovieMarkedAsFinished` | `_currentMovieMarkedAsFinished`:1393 | `false` → `true` | KILL, 10 assertions; `field-currentMovieMarkedAsFinished` |
| `field-currentMovieRewatchStarted` | `_currentMovieRewatchStarted`:1394 | `false` → `true` | KILL, 5 assertions; `field-currentMovieRewatchStarted` |
| `field-forceLocalCompletionTracking` | `_forceLocalCompletionTracking`:1696 | `false` → `true` | KILL, 4 assertions; `field-forceLocalCompletionTracking` |
| `field-movieCompletionThreshold-70` | `_movieCompletionThreshold`:1396 | `LocalCompletionStorage.defaultLocalCompletionThreshold` → `70` | KILL, 1 assertions; `field-movieCompletionThreshold-70` |
| `field-movieCompletionThreshold-90` | `_movieCompletionThreshold`:1396 | `LocalCompletionStorage.defaultLocalCompletionThreshold` → `90` | KILL, 2 assertions; `field-movieCompletionThreshold-90` |
| `field-episodeCompletionThreshold-70` | `_episodeCompletionThreshold`:1398 | `LocalCompletionStorage.defaultLocalCompletionThreshold` → `70` | KILL, 1 assertions; `field-episodeCompletionThreshold-70` |
| `field-episodeCompletionThreshold-90` | `_episodeCompletionThreshold`:1398 | `LocalCompletionStorage.defaultLocalCompletionThreshold` → `90` | KILL, 2 assertions; `field-episodeCompletionThreshold-90` |
| `threshold-movie-read` | `_loadLocalCompletionThresholds`:1677 | `LocalCompletionStorage.getMovieCompletionThreshold()` → `LocalCompletionStorage.getEpisodeCompletionThreshold()` | KILL, 1 assertions; `threshold-movie-read` |
| `threshold-episode-read` | `_loadLocalCompletionThresholds`:1678 | `LocalCompletionStorage.getEpisodeCompletionThreshold()` → `LocalCompletionStorage.getMovieCompletionThreshold()` | KILL, 2 assertions; `threshold-episode-read` |
| `threshold-mounted` | `_loadLocalCompletionThresholds`:1680 | `if (!mounted) return;` → `` | KILL, 1 assertions; `witness-threshold-mounted` |
| `threshold-movie-index` | `_loadLocalCompletionThresholds`:1681 | `values[0]` → `values[1]` | KILL, 1 assertions; `threshold-movie-index` |
| `threshold-episode-index` | `_loadLocalCompletionThresholds`:1682 | `values[1]` → `values[0]` | KILL, 2 assertions; `threshold-episode-index` |
| `threshold-movie-write` | `_loadLocalCompletionThresholds`:1681 | `_movieCompletionThreshold = values[0];` → `` | KILL, 1 assertions; `final2-threshold-movie-write` |
| `threshold-episode-write` | `_loadLocalCompletionThresholds`:1682 | `_episodeCompletionThreshold = values[1];` → `` | KILL, 3 assertions; `threshold-episode-write` |
| `threshold-reevaluate` | `_loadLocalCompletionThresholds`:1685 | `_checkAndApplyLocalCompletion();` → `` | KILL, 4 assertions; `threshold-reevaluate` |
| `policy-load` | `_loadTrackingPolicy`:1699 | `await TrackingSourcePolicy.load()` → `(await TrackingSourcePolicy.load()).forContent('medialibrary:mutant')` | KILL, 7 assertions; `policy-load` |
| `policy-content` | `_loadTrackingPolicy`:1700 | `_effectiveContentImdbId` → `null` | KILL, 2 assertions; `policy-content` |
| `policy-mounted` | `_loadTrackingPolicy`:1702 | `if (!mounted) return;` → `` | KILL, 1 assertions; `witness-policy-mounted` |
| `policy-force` | `_loadTrackingPolicy`:1703 | `policy.usesLocalCompletionTracking(` → `false && policy.usesLocalCompletionTracking(` | KILL, 5 assertions; `witness-policy-force` |
| `policy-trakt` | `_loadTrackingPolicy`:1704 | `traktScrobble: widget.traktScrobble` → `traktScrobble: false` | KILL, 1 assertions; `policy-trakt` |
| `policy-simkl` | `_loadTrackingPolicy`:1705 | `simklScrobble: widget.simklScrobble` → `simklScrobble: false` | KILL, 1 assertions; `policy-simkl` |
| `policy-mdblist` | `_loadTrackingPolicy`:1706 | `mdblistScrobble: widget.mdblistScrobble` → `mdblistScrobble: false` | KILL, 1 assertions; `policy-mdblist` |
| `policy-reevaluate` | `_loadTrackingPolicy`:1711 | `_checkAndApplyLocalCompletion();` → `` | KILL, 3 assertions; `policy-reevaluate` |
| `uses-force` | `_usesLocalCompletionTracking`:1689 | `_forceLocalCompletionTracking` → `false` | KILL, 10 assertions; `uses-force` |
| `uses-trakt` | `_usesLocalCompletionTracking`:1690 | `!widget.traktScrobble` → `true` | KILL, 6 assertions; `uses-trakt` |
| `uses-simkl` | `_usesLocalCompletionTracking`:1691 | `!widget.simklScrobble` → `true` | KILL, 2 assertions; `uses-simkl` |
| `uses-mdblist` | `_usesLocalCompletionTracking`:1692 | `!widget.mdblistScrobble` → `true` | KILL, 2 assertions; `uses-mdblist` |
| `uses-tv` | `_usesLocalCompletionTracking`:1693 | `widget.stremioTvChannels == null` → `true` | KILL, 1 assertions; `witness-uses-tv` |
| `uses-iptv` | `_usesLocalCompletionTracking`:1694 | `_effectiveIptvChannels == null` → `true` | KILL, 1 assertions; `witness-uses-iptv` |
| `movie-id-type` | `_currentLocalMovieImdbId`:1715 | `if (_effectiveContentType != 'movie') return null;` → `` | KILL, 2 assertions; `movie-id-type` |
| `movie-id-capture` | `_currentLocalMovieImdbId`:1716 | `_effectiveContentImdbId?.trim()` → `'tt7199999'` | KILL, 46 assertions; `witness-movie-id-capture` |
| `movie-id-trim` | `_currentLocalMovieImdbId`:1716 | `_effectiveContentImdbId?.trim()` → `_effectiveContentImdbId` | KILL, 1 assertions; `movie-id-trim` |
| `movie-id-empty` | `_currentLocalMovieImdbId`:1717 | `imdbId == null \|\| imdbId.isEmpty` → `imdbId == null` | KILL, 2 assertions; `movie-id-empty` |
| `reset-currentEpisodeMarkedAsFinished` | `_resetLocalCompletionState`:1721 | `_currentEpisodeMarkedAsFinished = false;` → `` | KILL, 3 assertions; `witness-reset-currentEpisodeMarkedAsFinished` |
| `reset-currentMovieMarkedAsFinished` | `_resetLocalCompletionState`:1722 | `_currentMovieMarkedAsFinished = false;` → `` | KILL, 1 assertions; `witness-reset-currentMovieMarkedAsFinished` |
| `reset-currentMovieRewatchStarted` | `_resetLocalCompletionState`:1723 | `_currentMovieRewatchStarted = false;` → `` | KILL, 1 assertions; `witness-reset-currentMovieRewatchStarted` |
| `episode-snapshot` | `_markCurrentEpisodeAsFinished`:9461 | `final seriesPlaylist = _seriesPlaylist;` → `final seriesPlaylist = null as SeriesPlaylist?;` | KILL, 7 assertions; `episode-snapshot` |
| `episode-single-series` | `_markCurrentEpisodeAsFinished`:9464 | `widget.contentType == 'series'` → `true` | KILL, 5 assertions; `final-series-episode-single-series` |
| `episode-single-season` | `_markCurrentEpisodeAsFinished`:9465 | `widget.contentSeason != null` → `true` | KILL, 1 assertions; `closure2-episode-single-season` |
| `episode-single-episode` | `_markCurrentEpisodeAsFinished`:9466 | `widget.contentEpisode != null` → `true` | KILL, 1 assertions; `closure2-episode-single-episode` |
| `episode-single-id` | `_markCurrentEpisodeAsFinished`:9467 | `widget.contentImdbId != null` → `true` | KILL, 1 assertions; `closure2-episode-single-id` |
| `episode-single-flag` | `_markCurrentEpisodeAsFinished`:9468 | `_currentEpisodeMarkedAsFinished = true;` → `` | KILL, 4 assertions; `episode-single-flag` |
| `episode-single-title` | `_markCurrentEpisodeAsFinished`:9471 | `widget.contentTitle ?? widget.title` → `widget.title` | KILL, 8 assertions; `final-series-episode-single-title` |
| `episode-single-fallback` | `_markCurrentEpisodeAsFinished`:9471 | `widget.contentTitle ?? widget.title` → `widget.contentTitle ?? 'changed title'` | KILL, 1 assertions; `episode-single-fallback` |
| `episode-single-season-value` | `_markCurrentEpisodeAsFinished`:9472 | `season: widget.contentSeason!` → `season: 99` | KILL, 10 assertions; `episode-single-season-value` |
| `episode-single-episode-value` | `_markCurrentEpisodeAsFinished`:9473 | `episode: widget.contentEpisode!` → `episode: 99` | KILL, 10 assertions; `episode-single-episode-value` |
| `episode-single-id-value` | `_markCurrentEpisodeAsFinished`:9474 | `imdbId: widget.contentImdbId` → `imdbId: 'tt7199999'` | KILL, 2 assertions; `witness-episode-single-id-value` |
| `episode-single-catch` | `_markCurrentEpisodeAsFinished`:9476 | `catch (_) {}` → `catch (_) { rethrow; }` | KILL, 1 assertions; `final2-episode-single-catch` |
| `episode-playlist-return` | `_markCurrentEpisodeAsFinished`:9481 | `seriesPlaylist.seriesTitle == null` → `false` | KILL, 1 assertions; `closure2-episode-playlist-return` |
| `episode-index-low` | `_markCurrentEpisodeAsFinished`:9487 | `_currentIndex >= 0` → `_currentIndex > 0` | KILL, 6 assertions; `episode-index-low` |
| `episode-index-high` | `_markCurrentEpisodeAsFinished`:9487 | `_currentIndex < _activePlaylist!.length` → `_currentIndex < _activePlaylist!.length - 1` | KILL, 1 assertions; `episode-index-high` |
| `episode-index-match` | `_markCurrentEpisodeAsFinished`:9489 | `episode.originalIndex == _currentIndex` → `episode.originalIndex == 99` | KILL, 2 assertions; `episode-index-match` |
| `episode-fallback` | `_markCurrentEpisodeAsFinished`:9490 | `orElse: () => seriesPlaylist.allEpisodes.first` → `orElse: () => seriesPlaylist.allEpisodes.last` | KILL, 1 assertions; `episode-fallback` |
| `episode-playlist-title` | `_markCurrentEpisodeAsFinished`:9496 | `seriesTitle: seriesPlaylist.seriesTitle!` → `seriesTitle: 'changed title'` | KILL, 3 assertions; `final-series-episode-playlist-title` |
| `episode-playlist-season` | `_markCurrentEpisodeAsFinished`:9497 | `season: currentEpisode.seriesInfo.season!` → `season: 99` | KILL, 6 assertions; `episode-playlist-season` |
| `episode-playlist-episode` | `_markCurrentEpisodeAsFinished`:9498 | `episode: currentEpisode.seriesInfo.episode!` → `episode: 99` | KILL, 6 assertions; `episode-playlist-episode` |
| `episode-playlist-id` | `_markCurrentEpisodeAsFinished`:9499 | `imdbId: seriesPlaylist.imdbId ?? widget.contentImdbId` → `imdbId: 'tt7199999'` | KILL, 2 assertions; `witness-episode-playlist-id` |
| `episode-playlist-id-fallback` | `_markCurrentEpisodeAsFinished`:9499 | `imdbId: seriesPlaylist.imdbId ?? widget.contentImdbId` → `imdbId: seriesPlaylist.imdbId` | KILL, 1 assertions; `episode-playlist-id-fallback` |
| `episode-playlist-id-preference` | `_markCurrentEpisodeAsFinished`:9499 | `imdbId: seriesPlaylist.imdbId ?? widget.contentImdbId` → `imdbId: widget.contentImdbId` | KILL, 1 assertions; `episode-playlist-id-preference` |
| `episode-playlist-catch` | `_markCurrentEpisodeAsFinished`:9503 | `catch (e) {}` → `catch (e) { rethrow; }` | KILL, 1 assertions; `closure2-episode-playlist-catch` |
| `episode-playlist-flag` | `_markCurrentEpisodeAsFinished`:9484 | `_currentEpisodeMarkedAsFinished = true;` → `` | KILL, 2 assertions; `witness-episode-playlist-flag` |
| `episode-metadata-season` | `_markCurrentEpisodeAsFinished`:9493 | `currentEpisode.seriesInfo.season != null` → `true` | EQUIVALENT, 0 assertions; `closure2-episode-metadata-season` |
| `episode-metadata-episode` | `_markCurrentEpisodeAsFinished`:9494 | `currentEpisode.seriesInfo.episode != null` → `true` | EQUIVALENT, 0 assertions; `closure2-episode-metadata-episode` |
| `movie-mark-tracking` | `_markCurrentMovieAsFinished`:9508 | `!_usesLocalCompletionTracking \|\|` → `false \|\|` | KILL, 7 assertions; `closure2-movie-mark-tracking` |
| `movie-mark-marked` | `_markCurrentMovieAsFinished`:9509 | `_currentMovieMarkedAsFinished \|\|` → `false \|\|` | KILL, 1 assertions; `closure2-movie-mark-marked` |
| `movie-mark-id` | `_markCurrentMovieAsFinished`:9507 | `final imdbId = _currentLocalMovieImdbId;` → `final imdbId = _currentLocalMovieImdbId ?? '';` | KILL, 2 assertions; `closure2-movie-mark-id` |
| `movie-mark-flag` | `_markCurrentMovieAsFinished`:9515 | `_currentMovieMarkedAsFinished = true;` → `` | KILL, 5 assertions; `movie-mark-flag` |
| `movie-mark-movie-write` | `_markCurrentMovieAsFinished`:9518 | `MovieProgressStorage.markMovieAsFinished(imdbId)` → `Future<void>.value()` | KILL, 7 assertions; `movie-mark-movie-write` |
| `movie-mark-resume-remove` | `_markCurrentMovieAsFinished`:9519 | `VideoResumeStorage.removeVideoResume( _resumeKey, playbackCheckpoint: true, )` → `Future<void>.value()` | KILL, 5 assertions; `movie-mark-resume-remove` |
| `movie-mark-resume-key` | `_markCurrentMovieAsFinished`:9520 | `_resumeKey` → `'wrong-key'` | KILL, 5 assertions; `movie-mark-resume-key` |
| `movie-mark-checkpoint` | `_markCurrentMovieAsFinished`:9521 | `playbackCheckpoint: true` → `playbackCheckpoint: false` | KILL, 1 assertions; `closure2-movie-mark-checkpoint` |
| `movie-mark-catch` | `_markCurrentMovieAsFinished`:9525 | `// Playback remains usable if local storage is temporarily unavailable.` → `rethrow;` | KILL, 3 assertions; `final2-movie-mark-catch` |
| `dispatch-movie-identity` | `_checkAndApplyLocalCompletion`:9541 | `final movieImdbId = _currentLocalMovieImdbId;` → `final movieImdbId = null as String?;` | KILL, 13 assertions; `dispatch-movie-identity` |
| `dispatch-validation` | `_checkAndApplyLocalCompletion`:9533 | `_validationGateActive \|\|` → `false \|\|` | KILL, 1 assertions; `witness-dispatch-validation` |
| `dispatch-tracking` | `_checkAndApplyLocalCompletion`:9534 | `!_usesLocalCompletionTracking \|\|` → `false \|\|` | KILL, 1 assertions; `closure2-dispatch-tracking` |
| `dispatch-duration` | `_checkAndApplyLocalCompletion`:9535 | `_duration <= Duration.zero` → `false` | KILL, 1 assertions; `witness-dispatch-duration` |
| `dispatch-position` | `_checkAndApplyLocalCompletion`:9536 | `_position <= Duration.zero` → `false` | KILL, 1 assertions; `witness-dispatch-position` |
| `dispatch-numerator` | `_checkAndApplyLocalCompletion`:9540 | `_position.inMicroseconds` → `_position.inMilliseconds` | KILL, 20 assertions; `dispatch-numerator` |
| `dispatch-denominator` | `_checkAndApplyLocalCompletion`:9540 | `_duration.inMicroseconds` → `_duration.inMilliseconds` | KILL, 17 assertions; `dispatch-denominator` |
| `dispatch-scale` | `_checkAndApplyLocalCompletion`:9540 | `* 100` → `* 10` | KILL, 20 assertions; `dispatch-scale` |
| `dispatch-rewatch-flag` | `_checkAndApplyLocalCompletion`:9543 | `!_currentMovieRewatchStarted &&` → `true &&` | KILL, 1 assertions; `final2-dispatch-rewatch-flag` |
| `dispatch-rewatch-threshold` | `_checkAndApplyLocalCompletion`:9543 | `percent < _movieCompletionThreshold` → `percent <= _movieCompletionThreshold` | KILL, 1 assertions; `closure2-dispatch-rewatch-threshold` |
| `dispatch-rewatch-assignment` | `_checkAndApplyLocalCompletion`:9547 | `_currentMovieRewatchStarted = true;` → `` | KILL, 1 assertions; `dispatch-rewatch-assignment` |
| `dispatch-unmark` | `_checkAndApplyLocalCompletion`:9548 | `unawaited(MovieProgressStorage.unmarkMovieAsFinished(movieImdbId));` → `` | KILL, 7 assertions; `dispatch-unmark` |
| `dispatch-movie-threshold` | `_checkAndApplyLocalCompletion`:9551 | `percent >= _movieCompletionThreshold` → `percent > _movieCompletionThreshold` | KILL, 3 assertions; `dispatch-movie-threshold` |
| `dispatch-movie-call` | `_checkAndApplyLocalCompletion`:9552 | `unawaited(_markCurrentMovieAsFinished());` → `` | KILL, 11 assertions; `dispatch-movie-call` |
| `dispatch-series-type` | `_checkAndApplyLocalCompletion`:9558 | `_effectiveContentType == 'series'` → `false` | KILL, 5 assertions; `dispatch-series-type` |
| `dispatch-series-playlist` | `_checkAndApplyLocalCompletion`:9558 | `_seriesPlaylist?.isSeries == true` → `false` | KILL, 1 assertions; `closure2-dispatch-series-playlist` |
| `dispatch-series-flag` | `_checkAndApplyLocalCompletion`:9560 | `_currentEpisodeMarkedAsFinished \|\|` → `false \|\|` | KILL, 6 assertions; `dispatch-series-flag` |
| `dispatch-series-threshold` | `_checkAndApplyLocalCompletion`:9561 | `percent < _episodeCompletionThreshold` → `percent <= _episodeCompletionThreshold` | KILL, 10 assertions; `dispatch-series-threshold` |
| `dispatch-series-call` | `_checkAndApplyLocalCompletion`:9564 | `unawaited(_markCurrentEpisodeAsFinished());` → `` | KILL, 9 assertions; `dispatch-series-call` |
| `dispatch-movie-flag` | `_checkAndApplyLocalCompletion`:9550 | `!_currentMovieMarkedAsFinished &&` → `true &&` | EQUIVALENT, 0 assertions; `final2-dispatch-movie-flag` |
| `ref-00` | `initState`:1630 | `_loadLocalCompletionThresholds()` → `Future<void>.value()` | KILL, 1 assertions; `final2-ref-00` |
| `ref-01` | `initState`:1628 | `_loadTrackingPolicy()` → `Future<void>.value()` | KILL, 11 assertions; `ref-01` |
| `ref-02` | `_bindPlayerInstanceSubscriptions`:2940 | `_checkAndApplyLocalCompletion()` → `(() {})()` | KILL, 3 assertions; `ref-02` |
| `ref-03` | `_onPlaybackEnded`:4348 | `_markCurrentEpisodeAsFinished()` → `Future<void>.value()` | KILL, 2 assertions; `witness-ref-03` |
| `ref-04` | `_onPlaybackEnded`:4352 | `_markCurrentMovieAsFinished()` → `Future<void>.value()` | KILL, 1 assertions; `witness-ref-04` |
| `ref-05` | `_goToNextEpisode`:5237 | `_resetLocalCompletionState()` → `(() {})()` | KILL, 3 assertions; `ref-05` |
| `ref-06` | `_switchToStremioTvChannel`:9030 | `_resetLocalCompletionState()` → `(() {})()` | KILL, 1 assertions; `ref-06` |
| `ref-07` | `_loadPlaylistIndexAttempt`:9770 | `_resetLocalCompletionState()` → `(() {})()` | KILL, 1 assertions; `ref-07` |
| `ref-08` | `_maybeRestoreResume`:11404 | `_currentLocalMovieImdbId` → `(null as String?)` | KILL, 2 assertions; `ref-08` |
| `ref-09` | `_saveResumeLocked`:11848 | `_currentMovieMarkedAsFinished` → `false` | KILL, 1 assertions; `ref-09` |
| `ref-10` | `_saveResumeLocked`:11848 | `_currentLocalMovieImdbId` → `(null as String?)` | KILL, 1 assertions; `ref-10` |
| `ast-056` | `_currentLocalMovieImdbId`:1717 | `return imdbId == null \|\| imdbId.isEmpty ? null : imdbId;` → `return 'changed';` | KILL, 45 assertions; `ast-056` |
| `ast-072` | `_markCurrentEpisodeAsFinished`:9463 | `seriesPlaylist == null \|\| !seriesPlaylist.isSeries` → `seriesPlaylist == null && !(seriesPlaylist?.isSeries ?? false)` | KILL, 1 assertions; `closure2-ast-072` |
| `ast-091` | `_markCurrentEpisodeAsFinished`:9477 | `return;` → `throw StateError('completion return mutation');` | KILL, 18 assertions; `ast-091` |
| `ast-094` | `_markCurrentEpisodeAsFinished`:9479 | `if (seriesPlaylist == null \|\| !seriesPlaylist.isSeries \|\| seriesPlaylist.seriesTitle == null) { return; }` → `if (seriesPlaylist == null \|\| !seriesPlaylist.isSeries \|\| seriesPlaylist.seriesTitle == null) { throw S...` | KILL, 1 assertions; `final-series-ast-094` |
| `ast-127` | `_markCurrentMovieAsFinished`:9510 | `if (!_usesLocalCompletionTracking \|\| _currentMovieMarkedAsFinished \|\| imdbId == null) { return; }` → `if (!_usesLocalCompletionTracking \|\| _currentMovieMarkedAsFinished \|\| imdbId == null) { throw StateErro...` | KILL, 11 assertions; `ast-127` |
| `ast-146` | `_checkAndApplyLocalCompletion`:9537 | `return;` → `throw StateError('completion return mutation');` | KILL, 88 assertions; `ast-146` |
| `ast-153` | `_checkAndApplyLocalCompletion`:9542 | `if (movieImdbId != null) { if (!_currentMovieRewatchStarted && percent < _movieCompletionThreshold) { // Th...` → `if (movieImdbId != null) { if (!_currentMovieRewatchStarted && percent < _movieCompletionThreshold) { // Th...` | KILL, 44 assertions; `ast-153` |
| `ast-179` | `_checkAndApplyLocalCompletion`:9559 | `if (!isSeries) return;` → `if (!isSeries) throw StateError('completion guarded return');` | KILL, 4 assertions; `ast-179` |
| `ast-185` | `_checkAndApplyLocalCompletion`:9562 | `return;` → `throw StateError('completion return mutation');` | KILL, 21 assertions; `ast-185` |
| `uses-always-off` | `_usesLocalCompletionTracking`:1689 | `(_forceLocalCompletionTracking \|\| (!widget.traktScrobble && !widget.simklScrobble && !widget.mdblistScrob...` → `false` | KILL, 9 assertions; `closure2-uses-always-off` |
| `uses-always-on` | `_usesLocalCompletionTracking`:1689 | `(_forceLocalCompletionTracking \|\| (!widget.traktScrobble && !widget.simklScrobble && !widget.mdblistScrob...` → `true` | KILL, 7 assertions; `closure2-uses-always-on` |
| `episode-index-upper-guard-removed` | `_markCurrentEpisodeAsFinished`:9487 | `_currentIndex < _activePlaylist!.length` → `true` | KILL, 1 assertions; `closure2-episode-index-upper-guard-removed` |
| `resume-finished-result` | `_maybeRestoreResume`:11408 | `MovieProgressStorage.isMovieFinished(localMovieImdbId)` → `Future<bool>.value(true)` | KILL, 1 assertions; `witness-resume-finished-result` |

### Final-input case witnesses

| Passing original case | Case file | Assertion-failing original run |
|---|---|---|
| Completion EOF does not invent an episode for non-series type collection | `video_player_completion_eof_test.dart` | `final-series-episode-single-series` |
| Completion EOF does not invent an episode for non-series type collection local | `video_player_completion_eof_test.dart` | `final-series-episode-single-series` |
| Completion EOF does not invent an episode for non-series type movie | `video_player_completion_eof_test.dart` | `final-series-episode-single-series` |
| Completion EOF does not invent an episode for non-series type movie local | `video_player_completion_eof_test.dart` | `witness-movie-id-capture` |
| Completion EOF does not invent an episode for non-series type null | `video_player_completion_eof_test.dart` | `final-series-episode-single-series` |
| Completion EOF does not invent an episode for non-series type null local | `video_player_completion_eof_test.dart` | `final-series-episode-single-series` |
| Completion EOF fanout awaits episode then movie cleanup before the end-of-item stop | `video_player_completion_eof_test.dart` | `witness-ref-04` |
| Completion MagicTV next resets movie completion and rewatch flags on the existing State | `video_player_completion_resets_test.dart` | `witness-reset-currentMovieRewatchStarted` |
| Completion MagicTV next resets series completion and rewatch flags on the existing State | `video_player_completion_resets_test.dart` | `witness-reset-currentEpisodeMarkedAsFinished` |
| Completion Stremio channel reset rearms episode position marking when the public guide input retires | `video_player_completion_resets_test.dart` | `witness-reset-currentEpisodeMarkedAsFinished` |
| Completion blank movie identity 0 leaves ordinary resume active | `video_player_completion_basic_test.dart` | `witness-movie-id-capture` |
| Completion blank movie identity 3 leaves ordinary resume active | `video_player_completion_basic_test.dart` | `witness-movie-id-capture` |
| Completion blank movie identity null leaves ordinary resume active | `video_player_completion_basic_test.dart` | `witness-movie-id-capture` |
| Completion caught episode failure spends position one-shot but EOF retries the physical write | `video_player_completion_failures_test.dart` | `final2-episode-single-catch` |
| Completion caught movie marker failure preserves partial cleanup and spends the resume-suppression guard | `video_player_completion_failures_test.dart` | `final2-movie-mark-catch` |
| Completion caught movie playback cleanup failure preserves partial cleanup and spends the resume-suppression guard | `video_player_completion_failures_test.dart` | `final2-movie-mark-catch` |
| Completion caught movie resume cleanup failure preserves partial cleanup and spends the resume-suppression guard | `video_player_completion_failures_test.dart` | `final2-movie-mark-catch` |
| Completion caught playlist write failure spends the position guard and EOF retries after storage recovers | `video_player_completion_playlist_boundaries_test.dart` | `closure2-episode-playlist-catch` |
| Completion content policy forces the native local owner for medialibrary:fixture-movie despite tracker intent | `video_player_completion_loads_test.dart` | `witness-policy-force` |
| Completion content policy forces the native local owner for tmdb:movie:7100000 despite tracker intent | `video_player_completion_loads_test.dart` | `witness-policy-force` |
| Completion early direct movie jump can be unmarked by a higher threshold while the completion guard remains spent | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion early movie default 80 then 50 re-evaluates while paused without another clock tick | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion early movie default 80 then 90 re-evaluates while paused without another clock tick | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion early movie initializer remains below 80 then marks at exact default equality before delivery | `video_player_completion_inputs_test.dart` | `witness-movie-id-capture` |
| Completion early series default 80 then 50 re-evaluates while paused without another clock tick | `video_player_completion_loads_test.dart` | `final-series-episode-single-title` |
| Completion early series default 80 then 90 re-evaluates while paused without another clock tick | `video_player_completion_loads_test.dart` | `final-series-episode-single-title` |
| Completion early series initializer remains below 80 then marks at exact default equality before delivery | `video_player_completion_inputs_test.dart` | `final-series-episode-single-title` |
| Completion first eligible movie position at exact threshold never starts a rewatch unmark | `video_player_completion_inputs_test.dart` | `closure2-dispatch-rewatch-threshold` |
| Completion forced local still excludes IPTV channels | `video_player_completion_loads_test.dart` | `witness-uses-iptv` |
| Completion forced local still excludes Stremio channels | `video_player_completion_loads_test.dart` | `witness-uses-tv` |
| Completion held episode read from A writes its map into B disposed=false and pins physical cleanup and resume ownership | `video_player_completion_profiles_test.dart` | `final-series-episode-single-title` |
| Completion held episode read from A writes its map into B disposed=true and pins physical cleanup and resume ownership | `video_player_completion_profiles_test.dart` | `final-series-episode-single-title` |
| Completion held mark read from A writes its map into B disposed=false and pins physical cleanup and resume ownership | `video_player_completion_profiles_test.dart` | `witness-movie-id-capture` |
| Completion held mark read from A writes its map into B disposed=true and pins physical cleanup and resume ownership | `video_player_completion_profiles_test.dart` | `witness-movie-id-capture` |
| Completion held rewatch unmark can remove the marker after a later completion without reviving resume saves | `video_player_completion_inputs_test.dart` | `witness-movie-id-capture` |
| Completion held unmark read from A writes its map into B disposed=false and pins physical cleanup and resume ownership | `video_player_completion_profiles_test.dart` | `witness-movie-id-capture` |
| Completion held unmark read from A writes its map into B disposed=true and pins physical cleanup and resume ownership | `video_player_completion_profiles_test.dart` | `witness-movie-id-capture` |
| Completion independent policy-first loader delivery with configured 70 pins the early mark and late rewatch | `video_player_completion_loads_test.dart` | `witness-policy-force` |
| Completion independent policy-first loader delivery with configured 90 pins the early mark and late rewatch | `video_player_completion_loads_test.dart` | `witness-policy-force` |
| Completion independent threshold-first loader delivery with configured 70 pins the early mark and late rewatch | `video_player_completion_loads_test.dart` | `witness-policy-force` |
| Completion independent threshold-first loader delivery with configured 90 pins the early mark and late rewatch | `video_player_completion_loads_test.dart` | `final2-threshold-movie-write` |
| Completion live mdblist widget selector permits local progress when the flag retires | `video_player_completion_inputs_test.dart` | `witness-movie-id-capture` |
| Completion live simkl widget selector permits local progress when the flag retires | `video_player_completion_inputs_test.dart` | `witness-movie-id-capture` |
| Completion live trakt widget selector permits local progress when the flag retires | `video_player_completion_inputs_test.dart` | `witness-movie-id-capture` |
| Completion local movie identity gates legacy resume and speed restoration finished=false | `video_player_completion_resume_test.dart` | `witness-resume-finished-result` |
| Completion local movie identity gates legacy resume and speed restoration finished=true | `video_player_completion_resume_test.dart` | `witness-movie-id-capture` |
| Completion malformed threshold read is uncaught and leaves both default thresholds usable | `video_player_completion_failures_test.dart` | `final2-ref-00` |
| Completion missing current playlist metadata falls back to the first remaining episode and EOF later retries the restored entry | `video_player_completion_playlist_test.dart` | `final-series-episode-playlist-title` |
| Completion missing single-file episode does not spend the guard and public widget delivery retries | `video_player_completion_inputs_test.dart` | `closure2-episode-single-episode` |
| Completion missing single-file identity does not spend the guard and public widget delivery retries | `video_player_completion_inputs_test.dart` | `closure2-episode-single-id` |
| Completion missing single-file season does not spend the guard and public widget delivery retries | `video_player_completion_inputs_test.dart` | `closure2-episode-single-season` |
| Completion missing single-file type does not spend the guard and public widget delivery retries | `video_player_completion_inputs_test.dart` | `final-series-episode-single-title` |
| Completion movie identity is trimmed before local completion and suppressing resume | `video_player_completion_basic_test.dart` | `witness-movie-id-capture` |
| Completion movie rewatch removes the marker once and preserves a subsequent external marker | `video_player_completion_basic_test.dart` | `witness-movie-id-capture` |
| Completion movie threshold 100 uses equality and performs cleanup only once | `video_player_completion_basic_test.dart` | `witness-movie-id-capture` |
| Completion movie threshold 50 uses equality and performs cleanup only once | `video_player_completion_basic_test.dart` | `witness-movie-id-capture` |
| Completion movie threshold 70 uses equality and performs cleanup only once | `video_player_completion_basic_test.dart` | `witness-movie-id-capture` |
| Completion movie threshold 80 uses equality and performs cleanup only once | `video_player_completion_basic_test.dart` | `witness-movie-id-capture` |
| Completion nameless forced series playlist remains unmarked on positions and repeated EOF | `video_player_completion_playlist_boundaries_test.dart` | `final-series-ast-094` |
| Completion nameless source replacement observes transient old index 0 before URL resolution and completion reset | `video_player_completion_source_window_test.dart` | `closure2-episode-playlist-return` |
| Completion nameless source replacement observes transient old index 1 before URL resolution and completion reset | `video_player_completion_source_window_test.dart` | `closure2-episode-index-upper-guard-removed` |
| Completion non-series playlist still uses single-file launch coordinates when catalog type is series | `video_player_completion_playlist_test.dart` | `closure2-ast-072` |
| Completion overlapping EOFs each write and an older completion can overwrite the newer timestamp | `video_player_completion_eof_test.dart` | `witness-ref-03` |
| Completion parsed series playlist supplies completion when catalog type is absent | `video_player_completion_playlist_boundaries_test.dart` | `closure2-dispatch-series-playlist` |
| Completion playlist missing episode spends its position guard before metadata and EOF is the later retry | `video_player_completion_playlist_test.dart` | `witness-episode-playlist-flag` |
| Completion playlist missing season spends its position guard before metadata and EOF is the later retry | `video_player_completion_playlist_test.dart` | `witness-episode-playlist-flag` |
| Completion playlist switch resets the position one-shot after target switching and marks the incoming episode | `video_player_completion_playlist_test.dart` | `witness-reset-currentEpisodeMarkedAsFinished` |
| Completion playlist uses parsed coordinates and enriched identity | `video_player_completion_playlist_test.dart` | `witness-episode-playlist-id` |
| Completion playlist uses parsed coordinates and launch fallback identity | `video_player_completion_playlist_test.dart` | `witness-episode-playlist-id` |
| Completion policy result delivered after disposal cannot mark the retained position | `video_player_completion_loads_test.dart` | `witness-policy-mounted` |
| Completion policy truth table flags=0 local=false | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion policy truth table flags=0 local=true | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion policy truth table flags=1 local=false | `video_player_completion_loads_test.dart` | `closure2-movie-mark-tracking` |
| Completion policy truth table flags=1 local=true | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion policy truth table flags=2 local=false | `video_player_completion_loads_test.dart` | `closure2-movie-mark-tracking` |
| Completion policy truth table flags=2 local=true | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion policy truth table flags=3 local=false | `video_player_completion_loads_test.dart` | `closure2-movie-mark-tracking` |
| Completion policy truth table flags=3 local=true | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion policy truth table flags=4 local=false | `video_player_completion_loads_test.dart` | `closure2-movie-mark-tracking` |
| Completion policy truth table flags=4 local=true | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion policy truth table flags=5 local=false | `video_player_completion_loads_test.dart` | `closure2-movie-mark-tracking` |
| Completion policy truth table flags=5 local=true | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion policy truth table flags=6 local=false | `video_player_completion_loads_test.dart` | `closure2-movie-mark-tracking` |
| Completion policy truth table flags=6 local=true | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion policy truth table flags=7 local=false | `video_player_completion_loads_test.dart` | `closure2-movie-mark-tracking` |
| Completion policy truth table flags=7 local=true | `video_player_completion_loads_test.dart` | `witness-movie-id-capture` |
| Completion position and EOF while startup open is held obey validation even with known duration | `video_player_completion_inputs_test.dart` | `witness-dispatch-validation` |
| Completion public stale playlist index -5 is clamped before marking | `video_player_completion_playlist_test.dart` | `final-series-episode-playlist-title` |
| Completion public stale playlist index 99 is clamped before marking | `video_player_completion_playlist_test.dart` | `final-series-episode-playlist-title` |
| Completion resume cleanup wakes playback sync for its profile rather than ordinary library scheduling | `video_player_completion_checkpoint_test.dart` | `closure2-movie-mark-checkpoint` |
| Completion series EOF ignores local enablement and position one-shot tracked=false | `video_player_completion_eof_test.dart` | `final-series-episode-single-title` |
| Completion series EOF ignores local enablement and position one-shot tracked=true | `video_player_completion_eof_test.dart` | `final-series-episode-single-title` |
| Completion single-file series chooses content title and exact episode coordinates | `video_player_completion_basic_test.dart` | `witness-episode-single-id-value` |
| Completion single-file series chooses fallback title and exact episode coordinates | `video_player_completion_basic_test.dart` | `witness-episode-single-id-value` |
| Completion threshold result delivered after disposal cannot mark the retained position | `video_player_completion_loads_test.dart` | `witness-threshold-mounted` |
| Completion unawaited rewatch failure escapes but its flag prevents another unmark | `video_player_completion_failures_test.dart` | `final2-dispatch-rewatch-flag` |
| Completion zero duration after a MagicTV reset cannot mark a positive position as infinite progress | `video_player_completion_resets_test.dart` | `witness-dispatch-duration` |
| Completion zero position after a MagicTV reset leaves the watched marker until real rewatch progress | `video_player_completion_resets_test.dart` | `witness-dispatch-position` |

### Baseline, checks and stop

The observed original baseline at the named merge reuses the P6 clean gate after
exact application/pubspec/analysis-config equality (recorded in
`p7/original/reuse.json`). Flutter 3.44.8 / Dart 3.12.2 are unchanged. The final
staged test tree `fc7da4dd02a78df9245b89688308bf66b500085a` records **13,291 success / 13 failure /
28 load error / 20 skip**. `suite_evidence.py compare` and the stricter comparison
of every old identity/outcome both pass: exactly **98 passing additions**, zero
changed/missing/fixed/newly skipped old identities. All additions are the declared
completion cases. The suite's exit 1 is the same original failures/load errors;
no failure allowlist or `test_baseline.py --record` is used. The suite has its final
completion event, and `final-suite.env.json` records no tree change during the run.
Subsequent edits are documentation/evidence only; all tested application and test
blobs remain exact. Commands: `nice -n 19 python3 dev/tool/suite_evidence.py run
vplayer/p7/step0/final-suite --no-pub
--dart-define=DEBRIFY_VP_TEST_HOOKS=true`; `suite_evidence.py compare --against
<p7>/original/baseline.jsonl <p7>/step0/final-suite.jsonl`. Full-suite nested
manifest/source-reader processes use the evidence wrapper's fresh isolated parser
packages with copied kernels deleted; Flutter suite processes are serialized.

| Check | Result |
|---|---|
| Original focused controls and systematic/replay commands (`nice -n 19 flutter test … --concurrency=1 --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true --reporter=json`) | Final 98-case control passes; 114 canonical points have assertion kills; three equivalence replays pass |
| Changed test/support `dart format --output=none --set-exit-if-changed` and `dart analyze` (both `nice -n 19`) | Fourteen files, zero formatting changes; no analyzer issues |
| `check_file_sizes.py`; `check_search_architecture.py` | 3,000 files / 140 ratchets; 1,668 migrated files pass; no baseline change |
| Step T manifest/history/analyzer checks reused | All 34 accepted commands still apply: no application/tool/manifest/config change since `98bf408f4`; all Dart self-tests, Kotlin 597 tests and P1–P6 named `--at` checks included |
| Original/source restoration and parser routing | All mutation runs use the verified named-base source and restore it; every manifest CLI and nested source parse uses its isolated `.dart_tool/vplayer_parser/` package with copied `*.dill` deleted |

Evidence: `p7/step0/points.json`, `ast-site-matrix.json`, `mutation-results.json`,
`coverage.json`, `equivalence-proofs.json`, `mutations/` and final suite/check logs.
Revision and tested-input hashes are recorded in `p7/step0/completion.json`.
No application/pubspec/CI/theme/source-guard/size-baseline changes, production
destination, bug fix, real network, push/merge/branch switch or device command.
The end-of-series manual local movie/episode/rewatch/This-device checklist remains
pending. Step 1, its registrations and its clean-tree gate are future work.
Stop after Step 0.

## Phase 7 independent sample — accepted Step 0 (2026-10-13)

Claude sampled original `e62a3a41f` (application identical to `2defa5100`).
All 20 valid mutations are reported as assertion kills: **20/20 (100%)**,
no compilation failures or exclusions. The accepted `results.json` and run
summary agree on the failed behavior identities; per-mutation files retain
log tails. Evidence: `p7/claude-sample/` and the hashed
`p7/step1/independent-sample-audit.json`. The systematic matrix remains
117 points: 114 kills / three equivalences; this independent sample adds no
coverage credit or tests. No Step-0b addendum is needed.

| Mutation | Contract | Assertion witness through original caller | Result |
|---|---|---|---|
| `j1` | Movie threshold loader index | Completion movie threshold 50 uses equality and performs cleanup only once | killed |
| `j2` | Threshold delivery re-evaluation | Completion early movie default 80 then 50 re-evaluates while paused without another clock tick | killed |
| `j3` | Stremio TV exclusion | Completion forced local still excludes Stremio channels | killed |
| `j4` | MDBList enabled exclusion | Completion live mdblist widget selector permits local progress when the flag retires | killed |
| `j5` | Movie type identity gate | Completion series EOF ignores local enablement and position one-shot tracked=false | killed |
| `j6` | Rewatch reset | Completion MagicTV next resets movie completion and rewatch flags on the existing State | killed |
| `j7` | Single-file IMDb gate | Completion missing single-file identity does not spend the guard and public widget delivery retries | killed |
| `j8` | Content title preference | Completion series EOF ignores local enablement and position one-shot tracked=false | killed |
| `j9` | Playlist current-index selection | Completion missing current playlist metadata falls back to the first remaining episode and EOF later retries the restored entry | killed |
| `j10` | Playlist IMDb preference | Completion playlist uses parsed coordinates and enriched identity | killed |
| `j11` | Movie resume cleanup | Completion caught movie marker failure preserves partial cleanup and spends the resume-suppression guard | killed |
| `j12` | Checkpoint cleanup flag | Completion resume cleanup wakes playback sync for its profile rather than ordinary library scheduling | killed |
| `j13` | Validation gate | Completion local movie identity gates legacy resume and speed restoration finished=true | killed |
| `j14` | Rewatch threshold equality | Completion first eligible movie position at exact threshold never starts a rewatch unmark | killed |
| `j15` | Rewatch unmark | Completion MagicTV next resets movie completion and rewatch flags on the existing State | killed |
| `j16` | Completion threshold equality | Completion resume cleanup wakes playback sync for its profile rather than ordinary library scheduling | killed |
| `j17` | Parsed series fallback | Completion parsed series playlist supplies completion when catalog type is absent | killed |
| `j18` | Episode threshold choice | Completion single-file series chooses content title and exact episode coordinates | killed |
| `j19` | Policy result | Completion series EOF ignores local enablement and position one-shot tracked=true | killed |
| `j20` | Policy delivery re-evaluation | Completion independent policy-first loader delivery with configured 70 pins the early mark and late rewatch | killed |

## Phase 7 Step 1 — production local completion (2026-10-13)

Applied `vplayer_p7.json`: 14 moves / 813 retained / one patched constructor;
11 retained substitutions; 21 frozen live Host getters and 16 protected prior
destinations. The local `seriesPlaylist` snapshot, EOF order, reset placement,
resume suppression and cross-profile writes stay as characterized. Inert
construction follows `_mdblist`. The 208-line destination and 16,974-line facade
are byte-identical to the accepted Step-T formatted materialization.

CI selects P7 for current/self and both analyzer manifest/inventory, retaining
P1–P6 named histories. Twelve behavior files and all theme/source path lists are
registered. Two newly unused frozen facade imports match the accepted probe;
the moved `empty_catches` identity retains its original symbol/multiplicity one.
No source-reader assertion needs retargeting in this phase. Current checker,
98-diagnostic scoped comparator/negatives, 143 focused tests, format, size and
architecture/negatives pass. Commands/hashes/revision: `p7/step1/completion.json`.
The full clean-tree gate follows; no behavior or pubspec change.

## Phase 7 gate fixture NOTE — original snapshot flake (2026-10-13)

The completed first clean gate at `cc430295d` has exactly one changed outcome:
Simkl suspended same-show episode snapshot expects 360 s but observes the 600 s
launch seek. Unmodified original `2defa5100` reproduces the exact assertion on
isolated run two (run one passes). The guide's background authenticated refresh
receives the synthetic empty Simkl response and can replace the seeded map;
an original trace observes the concurrent player reader loading `{}`. The empty
refresh path is confirmed in `SeriesBrowser._refreshTrackerSnapshots` and
`EpisodeTrackerSnapshotService.refreshSimkl`. Diagnostic edits are restored and
receive no pass/mutation credit.

Test-only stabilization holds the existing guide HTTP completer for every
snapshot race until the assertions finish, preserving the profile case and its
404 completion/cleanup. Earlier seek-wait and ordinal-boundary attempts failed
and are excluded. All 19 existing expectation calls and test-name tokens are
AST-identical. Entire file original/moved 3× controls pass (48 + 48), then the
final restored-original 16-case control passes. No added identity, deleted
assertion, application change or failure allowance. Format/analyzer pass.
The accepted Step-0 baseline remains the comparison target.

| Supplemental original mutation | Observable contract | Result |
|---|---|---|
| Simkl current-episode percentage +1 | Exact resumed duration through public episode selection, with the guide refresh held | assertion killed |
| MDBList current-episode percentage +1 | Exact resumed duration through public episode selection, with the guide refresh held | assertion killed |

Evidence: `p7/gate/fixture-note/` reproduction logs, rejected candidates,
non-credit traces, 3× controls, AST assertion proof, patches and mutation logs;
revision/input hashes in `completion.json`. The systematic P7 and independent
sample totals remain unchanged. New clean gate evidence follows separately.

## Phase 7 clean gate — local completion extraction (2026-10-13)

Clean fixture `dd2899773`, production `cc430295d`; comparison baseline is
accepted Step-0 `e62a3a41f` (original application `2defa5100`). Fresh full suite
matches all identities/outcomes: 13,291 success / 13 pre-existing failure /
28 pre-existing load error / 20 skip, zero additions/missing/changes. First
failed run remains excluded. The snapshot fixture NOTE counts are corrected:
16 behavior identities (loading/setup excluded), 48 original + 48 moved passes
across three controls, then 16 restored-original passes; all 19 expectations and
names are unchanged. Independent sample remains 20/20; systematic 114 kills /
three equivalences unchanged. No failure allowance or application bug fix.

All 36 manifest/Kotlin commands pass: 26 existing Dart self-tests, P7 universal
self/current/same-revision, six named histories and Kotlin 597 tests. Additional
post-fixture current check passes. Scoped analyzer: 98 occurrences / zero
additions, original empty-catch identity/multiplicity preserved; global warning
allowlist/negative tests, CI format, size and architecture pass. Parser copies
are isolated, kernels deleted, routing audited. Both clean APK and macOS release
builds pass; SDK unchanged, artifact hashes archived. Earlier move-check inputs
remain identical after the test-only fixture commit. Gate revision, commands,
all logs/hashes and equality audit: `p7/gate/completion.json`. Human local
completion/rewatch/This-device and prior device/PiP checklist remains pending.


## Phase 8 Step H — shared fixture hardening (2026-10-13)

Input `e42e152a4`; application remains byte-identical to original `491bf1fea`.
The shared action observer separates entry into a held boundary from completion.
Unheld actions settle; explicit held selections remain pending until their case
releases them. Normal public episode selections await completion. Fake player,
HTTP, cipher and storage-delivery lifetimes drain before streams close or the
transport resets. Existing timer observers and uncaught-error collectors remain
unchanged. Guide-refresh interception remains case-specific with the same
release and fallback response. No production code or dependency changed.

| Proof | Result / evidence |
| --- | --- |
| Existing names and assertions | Scanner-token identical across every existing video-player case; original shared-support expectations preserved when moved to the action helper. `p8/h/token-proof.json` |
| Pending assertions | Evidence-only logging before existing expectations on original application code; expanded case names, assertion sites and pending operation labels recorded per case in `p8/h/race-assertions.json` and final audit. Held incoming open and held seek remain concurrent; no global completion wait before their release. |
| Serial stress under load | Five complete replays of 43 tracker/completion/snapshot files, 313 behavior cases per replay (1,565 passes). File-loading events excluded from the case count. Concurrent nice-19 SHA-256 worker; zero assertion/error/load failures. `p8/h/closure-results.json` |
| Original mutation: Trakt exactly-80 conversion | `> 80` → `>= 80`: assertion failures in pause/start/heartbeat protocol expectations. |
| Original mutation: Simkl snapshot percent | Percent → percent+1: eight assertion failures against unchanged seek durations. |
| Original mutation: MDBList snapshot percent | Percent → percent+1: eight assertion failures against unchanged seek durations. |
| Original mutation: completion threshold | `>= movieCompletionThreshold` → `>`: five assertion failures against physical completion contents. |
| Original mutation: Trakt heartbeat cancellation | Remove cancellation from `stopTraktHeartbeat`: assertion failures including active timer during held incoming open. |
| Restoration / checks | All mutated production files restored; final control passes. Test analyzer has no issues; format, P7 exhaustive current guard, size and architecture pass. |

Mutation definitions and complete Expected/Actual logs are archived under
`p8/h/`; Flutter wraps assertion failures in generic `isFailure:false` runner
errors, so classification uses the actual TestFailure diagnostic and completed
run, not that flag. An initial inference attempt produced four dead-code warnings
(`Never` from dynamic callbacks); explicit `void` resolves them. A preliminary
focused run omitted the evidence-root variable and used the old P2 runtime
fallback: excluded from accepted proof; its 55 case directories were relocated
into P8, and the fixture fallback is now P8. The narrow birth-time relocation
ledger is `p8/h/runtime-path-note.json`; unrelated evidence was not touched.


## Phase 8 S2 — second characterization checkpoint (2026-10-13)

Follows test-only H `ef663d89d`; original application `491bf1fea`.
`VpS2Hooks` is separate from `VideoPlayerScreenTestHooks` (S), whose source,
installer and three interception points remain unchanged. It replaces only the
15 approved `Platform.isIOS/isAndroid` predicate occurrences in nine retained
facade declarations. Default getters call the same native predicate once; optional
callbacks are live. Installation has an explicit release/profile rejection,
`DEBRIFY_VP_TEST_HOOKS` rejection, then its sole assignment inside an assert.
No PiP/background implementation moved and the State constructor is unchanged.

| Patched original declaration | iOS / Android substitutions |
| --- | --- |
| `initState` (PiP registration) | 1 / 1 |
| `_bindPlayerInstanceSubscriptions` | 1 / 0 |
| `_openMedia` | 1 / 0 |
| `_setNativeSubtitleVisibilityForTrack` | 1 / 0 |
| `_buildSubtitleViewConfig` | 1 / 0 |
| `_enterPip` | 4 / 0 |
| `_armPipAutoEnter` | 1 / 0 |
| `_onPipModeChanged` | 1 / 0 |
| `_pauseForBackground` | 2 / 1 |

The exhaustive `vplayer_p8_seam.json` checkpoint classifies all 817 original
spans: nine patched declarations, all remaining spans retained, one frozen hook
scaffold, no destinations. Exact before→after/count patches preserve native
predicate evaluation and short-circuit order; tvOS checks stay unchanged. History
protects all 17 earlier destinations. CI current/self-test and analyzer manifest
select this checkpoint, retaining the unchanged P7 analyzer inventory and adding
P7 `--at 491bf1fea`; the P8 production ledger remains for Step 1. The validating
reader orders any checkpoint before its same-phase applied owner, preserving S
and supporting S2; restoring its former S-only ordering assertion-fails the new
registration case. The new source guard is registered with the existing hook flag.

| Proof / check | Result |
| --- | --- |
| Exhaustive checkpoint / original S | Zero ownership differences; S self-test and frozen-content/default proof PASS. |
| Independent S2 source/default/install guard | 13 negatives rejected: wrong native predicates, ignored/eager/twice override paths, missing release/profile/flag, outside-assert/second/other-member assignment, other-lib or facade installer reference. |
| Actual hook-body runtime controls | Five modes PASS: debug with flag, debug without flag, assertions disabled with flag, profile, compiled release. Native truth matrix and 16 registration short-circuit combinations pin defaults, order and counts; live/partial overrides pin callback counts. |
| Runtime mutations (independent from frozen-token comparison) | Seven assertion/error witnesses: wrong iOS native default; wrong Android native default; duplicate iOS default; installation outside assert; missing release rejection; missing profile rejection; missing flag rejection. All valid compilations; each fails a non-assert probe check with a `Bad state` diagnostic. |
| Fake player contract | Automatically distinct stable handles; explicit handle values and existing held/failed-operation controls. A held old handle returns its own value after the replacement handle arrives. Five new guard/contract cases PASS. |
| Focused hook-defined suite | 40 behavior cases PASS (S2, S, original mount smoke, Trakt snapshots, secondary boundary, validating source reader). Seven no-flag guard cases PASS separately. |
| Analyzer / formatter | 98 existing diagnostic occurrences, zero additions against P7 inventory. Raw/final declaration identities identical; two AST-optional inserted commas archived with offsets; no deleted commas; format idempotent. |
| Size / architecture / P7 history | PASS; facade 16,974 → 17,004 lines, explicit dated +30 seam allowance. No feature file added. |

Evidence is `p8/s2/`: manifests/source snapshots, token/comma proof, runtime
controls/negative compilations, complete suite logs, comparator/source-reader
results and hashes. Two longer candidate hook names caused formatter-induced
brace infos (four, then one); rejected candidates remain archived. Final name
`VpS2Hooks` preserves the original one-line guards and adds no diagnostics. A
focused command with a nonexistent smoke filename and an incorrectly rooted raw
analyzer command are excluded; corrected complete runs are archived. Pubspec,
original S, all earlier destinations and every other application file unchanged.
Native PiP presentation remains device-pending. No Phase-8 T, Step 0 or production
move; S2 stops for its independent review.


## Phase 8 Step T — PiP/lifecycle tooling (2026-10-13)

H/S2 independent review `vp-rev8s2`: no P1/P2/P3. Behavior ORIGINAL is S2
`21b19c944`; historical phase-7 merge `491bf1fea` stays the named `--at` target.
Complete `vplayer_p8.json` draft materializes only in `p8/tooling/`: all 818
original spans classified, 14 moves (including `_backgroundedAt`), 22 retained
occurrences, seven `PipService.isOwner(this)` → `_host.pipOwner` projections.
`Object get pipOwner => _s;` and all 33 Host interface members/adapter bodies
are frozen, including both live S2 predicates and exact tracker/display chains.
The State constructor appends `_pip` after `_completion`; the retained onPause
closure keeps recording teardown first and substitutes only its inner background
call. Five moved field initializers are inert, separately listed in
`p8/tooling/initializers.json`; no constructor or field initializer reads Host.

A necessary narrow opt-in extends the ownership layer: two explicit
`this.backgroundedAt` qualifications in `_resumeFromBackground` preserve the
captured local `backgroundedAt`. Without them, private→public renaming captures
the local and fails the binding guard. `owned_this_fields` validates a declared
exact counted substitution to a moved field in the same destination owner;
other `this` occurrences remain forbidden. Existing manifests have no opt-in
and retain their prior behavior. Negatives cover omitted/wrong field/count,
local capture, unsubstituted owner, cached/wrong predicate, wrong frozen owner,
constructor removal, captured player/time, fan-out/order, retained onPause and
dispose edits. Binding-only negatives independently reject unqualified time,
missing chain registration, bare predicate and tracker receiver changes.

All 26 existing Dart manifest self-tests, P1–P7 at
31a347ad2/fc24e32ae/890df14d8/315028407/ea7901ead/2defa5100/491bf1fea, and
Kotlin self-test PASS (34 commands); universal Dart self-test with the real P8
configuration/current S2 ledger, S and S2 proofs also PASS. Every Dart CLI parse
has an isolated copied package under ignored `.dart_tool/vplayer_parser`, copied
kernels deleted; nice-19 processes. `p8/tooling/checks.json`, `self.log`, S/S2
logs and parser routing record the commands/results.

Analyzer S2 root/strict/probe: 98/170/99 occurrences. The Host receiver adds one
`use_build_context_synchronously` info at original identity
`_VideoPlayerScreenState._enterPip`, with the unrelated-mounted-guard message;
existing `_enterPip` and earlier identities/multiplicities remain preserved in
the P8 inventory. Raw/formatted probe: 99, zero format-induced diagnostics.
AST optional-comma sites and formatter idempotence are archived; raw and
formatted splits compare with zero differences and protect all 17 earlier
files. Size/architecture/diff PASS. No production destination, application edit,
CI transition or pubspec change; Step 0 proceeds at S2.

An unmodified S2 full-suite pre-characterization run reproduces one unrelated
existing guide/profile race in the MDBList pending-checkpoint case: scoped
Trakt guide refresh raises `Profile session changed before async completion`.
No allowance; run excluded while original replays/fixture-only closure are
investigated in Step 0. Details under `p8/step0/`.

## Phase 8 Step 0 — original PiP, background and wakelock (2026-10-13)

Behavior ORIGINAL is independently reviewed S2 `21b19c944` (`vp-rev8s2`: no P1/P2/P3). Step T is `fcdfa03eb`; no production move. Ten behavior files / 90 cases use the real screen, its retained callbacks, lifecycle listener, real iOS route/session and synthetic channel/player/storage transports. No private State calls or source-text coverage credit.

All 327 statement/branch/literal/invocation/await AST sites in the 14 moves are inventoried in `p8/step0/ast-site-matrix.json`. Canonical overlap and guard/return grouping are explicit, with capture/transport explanations. The frozen 22 retained occurrences each have an independent point. The final inventory is **167 canonical points: 145 assertion kills, 12 source-proven equivalences with passing replays, 10 device-pending points**. Four additional contract/fixture witnesses also assertion-fail on original application files. Compilation errors and error-only failures are excluded; every one of the 90 new cases has an original assertion witness. Full commands, patches, complete JSONL logs, assertions and input hashes are under `p8/step0/`.

Ordinary mounts join the original six-second autosave registration before disposal; early-window assertions execute before that registration and only cleanup joins it. The fixture observes timers, never cancels application timers. It drains the playback/independent-owner queue before restoring both wakelock plugin interface references. The real Video widget has its own lifecycle and wakelock behavior: two pauses at normal background (State + Video), one Video pause when iOS State PiP suppresses its own pause; direct Video toggle writes are pinned alongside queued display-control writes.

### Coverage matrix — moved declarations

| Original declaration | Original caller / observable proof | Points: killed / equivalent / pending |
| --- | --- | --- |
| `_backgroundedAt` | Normal mobile pause stamps real wall time; a 31-second live absence retunes instead of playing. First renderer-replacement timestamp window remains pending. | 0 / 0 / 1 |
| `_iosPipStarting` | Early ready while audio setup is held; duplicate entry, background suppression, exact open/native/Flutter subtitle visibility; failure resets it. | 1 / 0 / 0 |
| `_iosPipDetached` | Parking, restored fullscreen owner loss, detached-owner close and replacement wake exemptions. | 1 / 0 / 0 |
| `_iosPipSession` | Inherited live assignment, null session, park/restore/dismiss, parked episode result and scoped State disposal while route remains mounted. | 0 / 1 / 0 |
| `_lastIosPipPositionSecond` | Initial second zero plus repeated/successive millisecond position ticks; exact iOS position/duration payload. | 1 / 0 / 0 |
| `_enterPip` | Public entry, lost owner, transition/starting/active guards; handle/subtitle/entry held across disposal, profile and real route replacement; errors and exact retry diagnostic/toast. | 22 / 2 / 3 |
| `_armPipAutoEnter` | Native readiness and late support, Android aspect/zero fallback payload; iOS no-op and lost-owner arming count. | 8 / 0 / 0 |
| `_pushPipState` | Playing and position streams, mode/entry, exact Android/iOS payloads and owner gate. | 9 / 0 / 0 |
| `_onPipModeChanged` | Collapse/auto-hide cancellation; native subtitle writes; real route park, edge-to-edge/all orientation order, dismissal and lifetime. | 12 / 1 / 0 |
| `_restoreIosPipPlayer` | Real landscape/portrait restore; held orientation across dispose/owner/profile/replacement; final frame ownership check and rejected orientation propagation. | 11 / 3 / 0 |
| `_onPipAction` | Every command/invalid input; redundant play/pause checked after each step; exact relative seek rounding/clamps; three-tracker payloads and timer cancellation order; early no-player callback. | 26 / 5 / 0 |
| `_pauseForBackground` | Valid transitions, no background resume write, user-pause physical A/B contents, pending/rejected pause, held playlist/Start Over, early next-key transition, recovery cancellation/pill clear; native recording/renderer paths pending. | 16 / 0 / 3 |
| `_resumeFromBackground` | Latch cleared before playing callback; user pause, late pause winner, sleep stop, real-clock live rejoin with exact diagnostic. | 10 / 0 / 3 |
| `_syncWakelock` | Initial acquisition; playing/buffering, pause/disposal, EOF with/without playing-false, held/rejected queue, independent owners and both replacement exemptions. | 1 / 0 / 0 |

### Frozen retained ledger — all 22 occurrences

| Occurrence point | Declaration / effect | Witness result |
| --- | --- | --- |
| `retained-session` | `_VideoPlayerScreenState.didChangeDependencies` at S2 line 1019 | killed: `retained-session` |
| `retained-pause` | `_VideoPlayerScreenState.initState` at S2 line 1545 | killed: `retained-pause` |
| `retained-resume` | `_VideoPlayerScreenState.initState` at S2 line 1547 | killed: `retained-resume` |
| `retained-mode` | `_VideoPlayerScreenState.initState` at S2 line 1587 | killed: `retained-mode` |
| `retained-action` | `_VideoPlayerScreenState.initState` at S2 line 1588 | killed: `retained-action` |
| `retained-restore` | `_VideoPlayerScreenState.initState` at S2 line 1589 | killed: `retained-restore` |
| `retained-support-arm` | `_VideoPlayerScreenState.initState` at S2 line 1594 | killed: `retained-support-arm` |
| `retained-ready-arm` | `_VideoPlayerScreenState._onPlayerInstanceReady` at S2 line 2229 | killed: `closure3-retained-ready-arm` |
| `retained-second-read` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions` at S2 line 2868 | killed: `retained-second-read` |
| `retained-second-write` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions` at S2 line 2869 | killed: `retained-second-write` |
| `retained-position-push` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions` at S2 line 2870 | killed: `retained-position-push` |
| `retained-playing-wake` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions` at S2 line 2946 | killed: `retained-playing-wake` |
| `retained-playing-push` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions` at S2 line 2947 | killed: `final-retained-playing-push` |
| `retained-open-starting` | `_VideoPlayerScreenState._openMedia` at S2 line 3922 | killed: `closure3-retained-open-starting` |
| `retained-subtitle-starting` | `_VideoPlayerScreenState._setNativeSubtitleVisibilityForTrack` at S2 line 4064 | killed: `retained-subtitle-starting` |
| `retained-result-park` | `_VideoPlayerScreenState._handleSeriesNextEpisode` at S2 line 5376 | killed: `retained-result-park` |
| `retained-result-close` | `_VideoPlayerScreenState._handleSeriesNextEpisode` at S2 line 5377 | killed: `retained-result-close` |
| `retained-dispose-detached` | `_VideoPlayerScreenState.dispose` at S2 line 10818 | killed: `retained-dispose-detached` |
| `retained-dispose-replaced` | `_VideoPlayerScreenState.dispose` at S2 line 10817 | killed: `retained-dispose-replaced` |
| `retained-dispose-close` | `_VideoPlayerScreenState.dispose` at S2 line 10819 | killed: `closure3-retained-dispose-close` |
| `retained-view-starting` | `_VideoPlayerScreenState._buildSubtitleViewConfig` at S2 line 12694 | killed: `closure3-retained-view-starting` |
| `retained-controls` | `_VideoPlayerScreenState.build` at S2 line 14280 | killed: `retained-controls` |

The retained onPause closure remains recording teardown first, then background pause; it never saves resume. Its order is frozen by the Step-T token comparison. Actual native mpv tee teardown cannot be reached on desktop: `DesktopRecordingService.isSupported` uses real `dart:io Platform` outside S2. It is explicitly device-pending, not counted as behavior-covered.

### Mutation table — canonical points

| Point | Original declaration / site | Mutation | Result / evidence run |
| --- | --- | --- | --- |
| `field-starting` | `_VideoPlayerScreenState._iosPipStarting`:10556 | `false` → `true` | killed; `field-starting` |
| `field-detached` | `_VideoPlayerScreenState._iosPipDetached`:10557 | `false` → `true` | killed; `field-detached` |
| `field-second` | `_VideoPlayerScreenState._lastIosPipPositionSecond`:10559 | `-1` → `0` | killed; `field-second` |
| `field-session` | `_VideoPlayerScreenState._iosPipSession`:10558 | `PlayerPipSession? _iosPipSession;` → `PlayerPipSession? _iosPipSession = PlayerPipSession((_) => const SizedBox());` | equivalent; `field-session` |
| `field-time` | `_VideoPlayerScreenState._backgroundedAt`:675 | `DateTime? _backgroundedAt;` → `DateTime? _backgroundedAt = DateTime(2000);` | device_pending; `device checklist` |
| `enterPip-owner` | `_VideoPlayerScreenState._enterPip`:10563 | `!PipService.isOwner(this) \|\|` → `false \|\|` | killed; `closure3-enterPip-owner` |
| `enterPip-created` | `_VideoPlayerScreenState._enterPip`:10564 | `!_playerCreated \|\|` → `false \|\|` | device_pending; `device checklist` |
| `enterPip-transition` | `_VideoPlayerScreenState._enterPip`:10565 | `_isTransitioning \|\|` → `false \|\|` | killed; `enterPip-transition` |
| `enterPip-starting` | `_VideoPlayerScreenState._enterPip`:10566 | `_iosPipStarting \|\|` → `false \|\|` | killed; `enterPip-starting` |
| `enterPip-active` | `_VideoPlayerScreenState._enterPip`:10567 | `_isPipActive)` → `false)` | killed; `enterPip-active` |
| `enterPip-start` | `_VideoPlayerScreenState._enterPip`:10570 | `setState(() => _iosPipStarting = true)` → `setState(() => _iosPipStarting = false)` | killed; `enterPip-start` |
| `enterPip-handle` | `_VideoPlayerScreenState._enterPip`:10573 | `await player.handle` → `0` | killed; `case-enterPip-handle` |
| `enterPip-post-mounted` | `_VideoPlayerScreenState._enterPip`:10574 | `!mounted \|\| !PipService.isOwner(this) \|\| !identical(player, _player)` → `!PipService.isOwner(this) \|\| !identical(player, _player)` | equivalent; `enterPip-post-mounted` |
| `enterPip-post-owner` | `_VideoPlayerScreenState._enterPip`:10574 | `!mounted \|\| !PipService.isOwner(this) \|\| !identical(player, _player)` → `!mounted \|\| !identical(player, _player)` | killed; `enterPip-post-owner` |
| `enterPip-post-player` | `_VideoPlayerScreenState._enterPip`:10574 | `!mounted \|\| !PipService.isOwner(this) \|\| !identical(player, _player)` → `!mounted \|\| !PipService.isOwner(this)` | device_pending; `device checklist` |
| `enterPip-subtitle` | `_VideoPlayerScreenState._enterPip`:10577 | `await _setNativeSubtitleVisibilityForTrack(player.state.track.subtitle);` → `<removed>` | killed; `case-enterPip-subtitle` |
| `enterPip-push` | `_VideoPlayerScreenState._enterPip`:10579 | `_pushPipState();` → `<removed>` | killed; `enterPip-push` |
| `enterPip-width` | `_VideoPlayerScreenState._enterPip`:10581 | `aspectWidth: player.state.width` → `aspectWidth: player.state.height` | killed; `enterPip-width` |
| `enterPip-height` | `_VideoPlayerScreenState._enterPip`:10582 | `aspectHeight: player.state.height` → `aspectHeight: player.state.width` | killed; `enterPip-height` |
| `enterPip-native-handle` | `_VideoPlayerScreenState._enterPip`:10583 | `playerHandle: handle` → `playerHandle: null` | killed; `enterPip-native-handle` |
| `enterPip-diagnostic` | `_VideoPlayerScreenState._enterPip`:10586 | `debugPrint('PiP entry failed: $error');` → `<removed>` | killed; `enterPip-diagnostic` |
| `enterPip-finally-mounted` | `_VideoPlayerScreenState._enterPip`:10588 | `mounted && PipService.isOwner(this) && identical(player, _player)` → `PipService.isOwner(this) && identical(player, _player)` | equivalent; `enterPip-finally-mounted` |
| `enterPip-finally-owner` | `_VideoPlayerScreenState._enterPip`:10588 | `mounted && PipService.isOwner(this) && identical(player, _player)` → `mounted && identical(player, _player)` | killed; `enterPip-finally-owner` |
| `enterPip-finally-player` | `_VideoPlayerScreenState._enterPip`:10588 | `mounted && PipService.isOwner(this) && identical(player, _player)` → `mounted && PipService.isOwner(this)` | device_pending; `device checklist` |
| `enterPip-clear` | `_VideoPlayerScreenState._enterPip`:10590 | `setState(() => _iosPipStarting = false);` → `<removed>` | killed; `enterPip-clear` |
| `enterPip-failure` | `_VideoPlayerScreenState._enterPip`:10595 | `if (!entered)` → `if (entered)` | killed; `case-enterPip-failure` |
| `enterPip-toast` | `_VideoPlayerScreenState._enterPip`:10603 | `Picture in Picture could not start. Please try again.` → `Changed retry` | killed; `enterPip-toast` |
| `enterPip-paused` | `_VideoPlayerScreenState._enterPip`:10597 | `AppLifecycleState.paused` → `AppLifecycleState.resumed` | killed; `enterPip-paused` |
| `enterPip-pause` | `_VideoPlayerScreenState._enterPip`:10598 | `_pauseForBackground();` → `<removed>` | killed; `enterPip-pause` |
| `armPipAutoEnter-ios` | `_VideoPlayerScreenState._armPipAutoEnter`:10616 | `if (VpS2Hooks.isIOS) return;` → `<removed>` | killed; `armPipAutoEnter-ios` |
| `armPipAutoEnter-owner` | `_VideoPlayerScreenState._armPipAutoEnter`:10617 | `if (!PipService.isOwner(this)) return;` → `<removed>` | killed; `closure3-armPipAutoEnter-owner` |
| `armPipAutoEnter-width` | `_VideoPlayerScreenState._armPipAutoEnter`:10618 | `final w = _player.state.width ?? 0;` → `final w = _player.state.height ?? 0;` | killed; `armPipAutoEnter-width` |
| `armPipAutoEnter-height` | `_VideoPlayerScreenState._armPipAutoEnter`:10619 | `final h = _player.state.height ?? 0;` → `final h = _player.state.width ?? 0;` | killed; `armPipAutoEnter-height` |
| `armPipAutoEnter-width-zero` | `_VideoPlayerScreenState._armPipAutoEnter`:10618 | `width ?? 0` → `width ?? 5` | killed; `armPipAutoEnter-width-zero` |
| `armPipAutoEnter-height-zero` | `_VideoPlayerScreenState._armPipAutoEnter`:10619 | `height ?? 0` → `height ?? 5` | killed; `armPipAutoEnter-height-zero` |
| `armPipAutoEnter-enable` | `_VideoPlayerScreenState._armPipAutoEnter`:10620 | `setAutoEnter(true` → `setAutoEnter(false` | killed; `armPipAutoEnter-enable` |
| `armPipAutoEnter-arm` | `_VideoPlayerScreenState._armPipAutoEnter`:10620 | `unawaited(PipService.setAutoEnter(true, aspectWidth: w, aspectHeight: h));` → `<removed>` | killed; `closure3-armPipAutoEnter-arm` |
| `pushPipState-owner` | `_VideoPlayerScreenState._pushPipState`:10627 | `if (!PipService.isOwner(this)) return;` → `<removed>` | killed; `pushPipState-owner` |
| `pushPipState-width-zero` | `_VideoPlayerScreenState._pushPipState`:10628 | `width ?? 0` → `width ?? 5` | killed; `pushPipState-width-zero` |
| `pushPipState-height-zero` | `_VideoPlayerScreenState._pushPipState`:10629 | `height ?? 0` → `height ?? 5` | killed; `pushPipState-height-zero` |
| `pushPipState-playing` | `_VideoPlayerScreenState._pushPipState`:10632 | `isPlaying: _isPlaying` → `isPlaying: !_isPlaying` | killed; `pushPipState-playing` |
| `pushPipState-next` | `_VideoPlayerScreenState._pushPipState`:10633 | `hasNext: _hasAnyNext` → `hasNext: false` | killed; `pushPipState-next` |
| `pushPipState-position` | `_VideoPlayerScreenState._pushPipState`:10634 | `positionMs: _player.state.position.inMilliseconds` → `positionMs: 0` | killed; `pushPipState-position` |
| `pushPipState-duration` | `_VideoPlayerScreenState._pushPipState`:10635 | `durationMs: _player.state.duration.inMilliseconds` → `durationMs: 0` | killed; `pushPipState-duration` |
| `pushPipState-width` | `_VideoPlayerScreenState._pushPipState`:10636 | `aspectWidth: w` → `aspectWidth: h` | killed; `pushPipState-width` |
| `pushPipState-height` | `_VideoPlayerScreenState._pushPipState`:10637 | `aspectHeight: h` → `aspectHeight: w` | killed; `pushPipState-height` |
| `onPipModeChanged-mounted` | `_VideoPlayerScreenState._onPipModeChanged`:10645 | `if (!mounted) return;` → `<removed>` | equivalent; `onPipModeChanged-mounted` |
| `onPipModeChanged-cancel` | `_VideoPlayerScreenState._onPipModeChanged`:10647 | `_hideTimer?.cancel();` → `<removed>` | killed; `onPipModeChanged-cancel` |
| `onPipModeChanged-hide` | `_VideoPlayerScreenState._onPipModeChanged`:10648 | `_controlsVisible.value = false;` → `_controlsVisible.value = true;` | killed; `onPipModeChanged-hide` |
| `onPipModeChanged-push` | `_VideoPlayerScreenState._onPipModeChanged`:10649 | `_pushPipState();` → `<removed>` | killed; `onPipModeChanged-push` |
| `onPipModeChanged-active` | `_VideoPlayerScreenState._onPipModeChanged`:10651 | `setState(() => _isPipActive = inPip);` → `setState(() => _isPipActive = false);` | killed; `onPipModeChanged-active` |
| `onPipModeChanged-ios` | `_VideoPlayerScreenState._onPipModeChanged`:10652 | `VpS2Hooks.isIOS && _playerCreated` → `false` | killed; `onPipModeChanged-ios` |
| `onPipModeChanged-park` | `_VideoPlayerScreenState._onPipModeChanged`:10653 | `_iosPipSession?.park() ?? false` → `false` | killed; `case-onPipModeChanged-park` |
| `onPipModeChanged-detached` | `_VideoPlayerScreenState._onPipModeChanged`:10654 | `_iosPipDetached = true;` → `<removed>` | killed; `onPipModeChanged-detached` |
| `onPipModeChanged-ui` | `_VideoPlayerScreenState._onPipModeChanged`:10655 | `SystemUiMode.edgeToEdge` → `SystemUiMode.immersiveSticky` | killed; `onPipModeChanged-ui` |
| `onPipModeChanged-orientations` | `_VideoPlayerScreenState._onPipModeChanged`:10657 | `DeviceOrientation.values` → `const [DeviceOrientation.portraitUp]` | killed; `onPipModeChanged-orientations` |
| `onPipModeChanged-close` | `_VideoPlayerScreenState._onPipModeChanged`:10662 | `_iosPipSession?.close();` → `<removed>` | killed; `onPipModeChanged-close` |
| `onPipModeChanged-close-branch` | `_VideoPlayerScreenState._onPipModeChanged`:10659 | `!inPip && (_iosPipSession?.isParked ?? false)` → `false` | killed; `onPipModeChanged-close-branch` |
| `onPipModeChanged-subtitle` | `_VideoPlayerScreenState._onPipModeChanged`:10666 | `_setNativeSubtitleVisibilityForTrack(_player.state.track.subtitle)` → `Future<void>.value()` | killed; `onPipModeChanged-subtitle` |
| `restoreIosPipPlayer-mounted` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10672 | `!mounted \|\| !PipService.isOwner(this)` → `!PipService.isOwner(this)` | equivalent; `restoreIosPipPlayer-mounted` |
| `restoreIosPipPlayer-owner` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10672 | `!mounted \|\| !PipService.isOwner(this)` → `!mounted` | equivalent; `restoreIosPipPlayer-owner` |
| `restoreIosPipPlayer-session` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10674 | `if (session == null) return false;` → `if (session == null) return true;` | killed; `restoreIosPipPlayer-session` |
| `restoreIosPipPlayer-restore` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10675 | `session.isParked && !session.restore()` → `session.isParked` | killed; `restoreIosPipPlayer-restore` |
| `restoreIosPipPlayer-detached` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10676 | `_iosPipDetached = false;` → `<removed>` | killed; `closure3-restoreIosPipPlayer-detached` |
| `restoreIosPipPlayer-orientation` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10678 | `_display.landscapeLocked` → `!_display.landscapeLocked` | killed; `case-restoreIosPipPlayer-orientation` |
| `restoreIosPipPlayer-left` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10680 | `DeviceOrientation.landscapeLeft` → `DeviceOrientation.portraitDown` | killed; `restoreIosPipPlayer-left` |
| `restoreIosPipPlayer-right` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10681 | `DeviceOrientation.landscapeRight` → `DeviceOrientation.portraitDown` | killed; `restoreIosPipPlayer-right` |
| `restoreIosPipPlayer-portrait` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10683 | `DeviceOrientation.portraitUp` → `DeviceOrientation.portraitDown` | killed; `restoreIosPipPlayer-portrait` |
| `restoreIosPipPlayer-ui` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10685 | `SystemUiMode.immersiveSticky` → `SystemUiMode.edgeToEdge` | killed; `restoreIosPipPlayer-ui` |
| `restoreIosPipPlayer-frame` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10686 | `await WidgetsBinding.instance.endOfFrame;` → `<removed>` | killed; `restoreIosPipPlayer-frame` |
| `restoreIosPipPlayer-return-mounted` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10687 | `return mounted && PipService.isOwner(this);` → `return PipService.isOwner(this);` | equivalent; `restoreIosPipPlayer-return-mounted` |
| `restoreIosPipPlayer-return-owner` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10687 | `return mounted && PipService.isOwner(this);` → `return mounted;` | killed; `restoreIosPipPlayer-return-owner` |
| `onPipAction-mounted` | `_VideoPlayerScreenState._onPipAction`:10692 | `!mounted \|\| !_playerCreated` → `!_playerCreated` | equivalent; `onPipAction-mounted` |
| `onPipAction-created` | `_VideoPlayerScreenState._onPipAction`:10692 | `!mounted \|\| !_playerCreated` → `!mounted` | killed; `closure3-onPipAction-created` |
| `onPipAction-prefix` | `_VideoPlayerScreenState._onPipAction`:10693 | `startsWith('seek:')` → `startsWith('seek')` | killed; `closure3-onPipAction-prefix` |
| `onPipAction-parse` | `_VideoPlayerScreenState._onPipAction`:10694 | `substring(5)` → `substring(4)` | killed; `closure3-onPipAction-parse` |
| `onPipAction-finite` | `_VideoPlayerScreenState._onPipAction`:10695 | `seconds == null \|\| !seconds.isFinite \|\| _isTransitioning` → `seconds == null \|\| _isTransitioning` | killed; `closure3-onPipAction-finite` |
| `onPipAction-transition` | `_VideoPlayerScreenState._onPipAction`:10695 | `seconds == null \|\| !seconds.isFinite \|\| _isTransitioning` → `seconds == null \|\| !seconds.isFinite` | killed; `onPipAction-transition` |
| `onPipAction-sum` | `_VideoPlayerScreenState._onPipAction`:10697 | `_player.state.position.inMilliseconds +` → `<removed>` | killed; `onPipAction-sum` |
| `onPipAction-scale` | `_VideoPlayerScreenState._onPipAction`:10697 | `seconds * 1000` → `seconds * 100` | killed; `onPipAction-scale` |
| `onPipAction-round` | `_VideoPlayerScreenState._onPipAction`:10697 | `(seconds * 1000).round()` → `(seconds * 1000).truncate()` | killed; `onPipAction-round` |
| `onPipAction-lower` | `_VideoPlayerScreenState._onPipAction`:10698 | `.clamp(0,` → `.clamp(1,` | killed; `onPipAction-lower` |
| `onPipAction-upper` | `_VideoPlayerScreenState._onPipAction`:10698 | `_player.state.duration.inMilliseconds);` → `_player.state.duration.inMilliseconds + 1);` | killed; `onPipAction-upper` |
| `onPipAction-seek` | `_VideoPlayerScreenState._onPipAction`:10700 | `unawaited(_player.seek(position));` → `<removed>` | killed; `onPipAction-seek` |
| `onPipAction-trakt` | `_VideoPlayerScreenState._onPipAction`:10701 | `_trakt.traktScrobbleSeek(position);` → `<removed>` | killed; `onPipAction-trakt` |
| `onPipAction-simkl` | `_VideoPlayerScreenState._onPipAction`:10702 | `_simkl.simklScrobbleSeek(position);` → `<removed>` | killed; `onPipAction-simkl` |
| `onPipAction-mdblist` | `_VideoPlayerScreenState._onPipAction`:10703 | `_mdblist.mdblistScrobbleSeek(position);` → `<removed>` | killed; `onPipAction-mdblist` |
| `onPipAction-order` | `_VideoPlayerScreenState._onPipAction`:10701 | `_trakt.traktScrobbleSeek(position);       _simkl.simklScrobbleSeek(position);` → `_simkl.simklScrobbleSeek(position);       _trakt.traktScrobbleSeek(position);` | killed; `onPipAction-order` |
| `onPipAction-play` | `_VideoPlayerScreenState._onPipAction`:10707 | `case 'play':` → `case 'changed-play':` | killed; `onPipAction-play` |
| `onPipAction-play-gate` | `_VideoPlayerScreenState._onPipAction`:10708 | `if (!_isPlaying) _togglePlay();` → `_togglePlay();` | killed; `closure3-onPipAction-play-gate` |
| `onPipAction-pause` | `_VideoPlayerScreenState._onPipAction`:10710 | `case 'pause':` → `case 'changed-pause':` | killed; `onPipAction-pause` |
| `onPipAction-pause-gate` | `_VideoPlayerScreenState._onPipAction`:10711 | `if (_isPlaying) _togglePlay();` → `_togglePlay();` | killed; `closure3-onPipAction-pause-gate` |
| `onPipAction-toggle` | `_VideoPlayerScreenState._onPipAction`:10713 | `case 'playpause':         _togglePlay();` → `case 'playpause':         break;` | killed; `onPipAction-toggle` |
| `onPipAction-next` | `_VideoPlayerScreenState._onPipAction`:10717 | `if (_hasAnyNext) _goToNextEpisode();` → `<removed>` | killed; `closure3-onPipAction-next` |
| `pauseForBackground-mobile` | `_VideoPlayerScreenState._pauseForBackground`:10728 | `if (!VpS2Hooks.isAndroid && !VpS2Hooks.isIOS) return;` → `<removed>` | killed; `pauseForBackground-mobile` |
| `pauseForBackground-pip` | `_VideoPlayerScreenState._pauseForBackground`:10729 | `(_isPipActive \|\| _iosPipStarting)` → `false` | killed; `pauseForBackground-pip` |
| `pauseForBackground-cancel` | `_VideoPlayerScreenState._pauseForBackground`:10732 | `_cancelPendingIptvCatchup(hideFeedback: false);` → `<removed>` | killed; `pauseForBackground-cancel` |
| `pauseForBackground-feedback` | `_VideoPlayerScreenState._pauseForBackground`:10732 | `hideFeedback: false` → `hideFeedback: true` | killed; `pauseForBackground-feedback` |
| `pauseForBackground-renderer` | `_VideoPlayerScreenState._pauseForBackground`:10736 | `if (_rendererFallbackInProgress)` → `if (false)` | device_pending; `device checklist` |
| `pauseForBackground-renderer-latch` | `_VideoPlayerScreenState._pauseForBackground`:10737 | `_pausedByLifecycle = true;` → `<removed>` | device_pending; `device checklist` |
| `pauseForBackground-renderer-pause` | `_VideoPlayerScreenState._pauseForBackground`:10738 | `if (_playerCreated) unawaited(_player.pause());` → `<removed>` | device_pending; `device checklist` |
| `pauseForBackground-created` | `_VideoPlayerScreenState._pauseForBackground`:10750 | `!_playerCreated \|\|` → `false \|\|` | killed; `closure3-pauseForBackground-created` |
| `pauseForBackground-playing` | `_VideoPlayerScreenState._pauseForBackground`:10751 | `!_isPlaying && !_isTransitioning && !openingStartOver` → `!_isTransitioning && !openingStartOver` | killed; `pauseForBackground-playing` |
| `pauseForBackground-transition` | `_VideoPlayerScreenState._pauseForBackground`:10751 | `!_isPlaying && !_isTransitioning && !openingStartOver` → `!_isPlaying && !openingStartOver` | killed; `pauseForBackground-transition` |
| `pauseForBackground-startover` | `_VideoPlayerScreenState._pauseForBackground`:10751 | `!_isPlaying && !_isTransitioning && !openingStartOver` → `!_isPlaying && !_isTransitioning` | killed; `pauseForBackground-startover` |
| `pauseForBackground-time` | `_VideoPlayerScreenState._pauseForBackground`:10756 | `_backgroundedAt = DateTime.now();` → `<removed>` | killed; `pauseForBackground-time` |
| `pauseForBackground-recovery` | `_VideoPlayerScreenState._pauseForBackground`:10757 | `_iptvLiveRecovery.cancel();` → `<removed>` | killed; `closure3-pauseForBackground-recovery` |
| `pauseForBackground-reconnect` | `_VideoPlayerScreenState._pauseForBackground`:10758 | `_iptvReconnectText.value = null;` → `<removed>` | killed; `closure3-pauseForBackground-reconnect` |
| `pause-primary-latch` | `_VideoPlayerScreenState._pauseForBackground`:10759 | `_pausedByLifecycle = true;` → `<removed>` | killed; `case-pause-primary-latch` |
| `pause-primary-call` | `_VideoPlayerScreenState._pauseForBackground`:10760 | `unawaited(_player.pause());` → `<removed>` | killed; `pause-primary-call` |
| `resumeFromBackground-latch` | `_VideoPlayerScreenState._resumeFromBackground`:10767 | `if (!_pausedByLifecycle) return;` → `<removed>` | killed; `resumeFromBackground-latch` |
| `resumeFromBackground-clear` | `_VideoPlayerScreenState._resumeFromBackground`:10771 | `_pausedByLifecycle = false;` → `<removed>` | killed; `resumeFromBackground-clear` |
| `resumeFromBackground-renderer` | `_VideoPlayerScreenState._resumeFromBackground`:10775 | `if (_rendererFallbackInProgress) return;` → `<removed>` | device_pending; `device checklist` |
| `resumeFromBackground-created` | `_VideoPlayerScreenState._resumeFromBackground`:10776 | `if (!_playerCreated \|\| !mounted) return;` → `<removed>` | device_pending; `device checklist` |
| `resumeFromBackground-sleep` | `_VideoPlayerScreenState._resumeFromBackground`:10780 | `if (_sleepStopLatched) return;` → `<removed>` | killed; `resumeFromBackground-sleep` |
| `resumeFromBackground-time-clear` | `_VideoPlayerScreenState._resumeFromBackground`:10786 | `_backgroundedAt = null;` → `<removed>` | device_pending; `device checklist` |
| `resumeFromBackground-live` | `_VideoPlayerScreenState._resumeFromBackground`:10787 | `_currentIptvChannel?.isLive == true` → `false` | killed; `resumeFromBackground-live` |
| `resumeFromBackground-startover` | `_VideoPlayerScreenState._resumeFromBackground`:10788 | `!_iptvStartOverActive &&` → `false &&` | killed; `resumeFromBackground-startover` |
| `resumeFromBackground-absent` | `_VideoPlayerScreenState._resumeFromBackground`:10789 | `backgroundedAt != null &&` → `backgroundedAt != null && false &&` | killed; `closure3-resumeFromBackground-absent` |
| `resumeFromBackground-threshold` | `_VideoPlayerScreenState._resumeFromBackground`:10791 | `const Duration(seconds: 30)` → `const Duration(seconds: 300)` | killed; `resumeFromBackground-threshold` |
| `resumeFromBackground-retry` | `_VideoPlayerScreenState._resumeFromBackground`:10792 | `_iptvLiveRecovery.userRetry('lifecycle-rejoin');` → `<removed>` | killed; `resumeFromBackground-retry` |
| `resumeFromBackground-source` | `_VideoPlayerScreenState._resumeFromBackground`:10792 | `userRetry('lifecycle-rejoin')` → `userRetry('changed')` | killed; `closure3-resumeFromBackground-source` |
| `resumeFromBackground-play` | `_VideoPlayerScreenState._resumeFromBackground`:10795 | `unawaited(_player.play());` → `<removed>` | killed; `resumeFromBackground-play` |
| `sync-wake` | `_VideoPlayerScreenState._syncWakelock`:10806 | `setWakelock(playing)` → `setWakelock(!playing)` | killed; `sync-wake` |
| `retained-session` | `_VideoPlayerScreenState.didChangeDependencies`:1019 | `_iosPipSession = PlayerPipSession.of(context);` → `_iosPipSession = null;` | killed; `retained-session` |
| `retained-pause` | `_VideoPlayerScreenState.initState`:1545 | `_pauseForBackground();` → `<removed>` | killed; `retained-pause` |
| `retained-resume` | `_VideoPlayerScreenState.initState`:1547 | `onResume: _resumeFromBackground` → `onResume: () {}` | killed; `retained-resume` |
| `retained-mode` | `_VideoPlayerScreenState.initState`:1587 | `onMode: _onPipModeChanged` → `onMode: (_) {}` | killed; `retained-mode` |
| `retained-action` | `_VideoPlayerScreenState.initState`:1588 | `onAction: _onPipAction` → `onAction: (_) {}` | killed; `retained-action` |
| `retained-restore` | `_VideoPlayerScreenState.initState`:1589 | `onRestore: _restoreIosPipPlayer` → `onRestore: () async => false` | killed; `retained-restore` |
| `retained-support-arm` | `_VideoPlayerScreenState.initState`:1594 | `if (_isReady) _armPipAutoEnter();` → `<removed>` | killed; `retained-support-arm` |
| `retained-ready-arm` | `_VideoPlayerScreenState._onPlayerInstanceReady`:2229 | `_armPipAutoEnter();` → `<removed>` | killed; `closure3-retained-ready-arm` |
| `retained-second-read` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions`:2868 | `d.inSeconds != _lastIosPipPositionSecond` → `d.inSeconds == _lastIosPipPositionSecond` | killed; `retained-second-read` |
| `retained-second-write` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions`:2869 | `_lastIosPipPositionSecond = d.inSeconds;` → `<removed>` | killed; `retained-second-write` |
| `retained-position-push` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions`:2870 | `_pushPipState();` → `<removed>` | killed; `retained-position-push` |
| `retained-playing-wake` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions`:2946 | `_syncWakelock(p);` → `<removed>` | killed; `retained-playing-wake` |
| `retained-playing-push` | `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions`:2947 | `_pushPipState();` → `<removed>` | killed; `final-retained-playing-push` |
| `retained-open-starting` | `_VideoPlayerScreenState._openMedia`:3922 | `_isPipActive \|\| _iosPipStarting` → `_isPipActive` | killed; `closure3-retained-open-starting` |
| `retained-subtitle-starting` | `_VideoPlayerScreenState._setNativeSubtitleVisibilityForTrack`:4064 | `_isPipActive \|\| _iosPipStarting` → `_isPipActive` | killed; `retained-subtitle-starting` |
| `retained-result-park` | `_VideoPlayerScreenState._handleSeriesNextEpisode`:5376 | `_iosPipSession?.isParked ?? false` → `false` | killed; `retained-result-park` |
| `retained-result-close` | `_VideoPlayerScreenState._handleSeriesNextEpisode`:5377 | `_iosPipSession!.close(result);` → `<removed>` | killed; `retained-result-close` |
| `retained-dispose-detached` | `_VideoPlayerScreenState.dispose`:10818 | `_iosPipDetached && !PipService.isOwner(this)` → `false` | killed; `retained-dispose-detached` |
| `retained-dispose-replaced` | `_VideoPlayerScreenState.dispose`:10817 | `_iosPipSession?.wasReplaced ?? false` → `false` | killed; `retained-dispose-replaced` |
| `retained-dispose-close` | `_VideoPlayerScreenState.dispose`:10819 | `_iosPipSession?.close();` → `<removed>` | killed; `closure3-retained-dispose-close` |
| `retained-view-starting` | `_VideoPlayerScreenState._buildSubtitleViewConfig`:12694 | `_isPipActive \|\| _iosPipStarting` → `_isPipActive` | killed; `closure3-retained-view-starting` |
| `retained-controls` | `_VideoPlayerScreenState.build`:14280 | `? _enterPip` → `? () async {}` | killed; `retained-controls` |
| `enterPip-entered-default` | `_VideoPlayerScreenState._enterPip`:10571 | `var entered = false;` → `var entered = true;` | killed; `enterPip-entered-default` |
| `enterPip-finally-subtitle` | `_VideoPlayerScreenState._enterPip`:10592 | `_setNativeSubtitleVisibilityForTrack(player.state.track.subtitle)` → `Future<void>.value()` | killed; `enterPip-finally-subtitle` |
| `onPipAction-position-unit` | `_VideoPlayerScreenState._onPipAction`:10699 | `Duration(milliseconds: target)` → `Duration(microseconds: target)` | killed; `onPipAction-position-unit` |
| `onPipAction-next-label` | `_VideoPlayerScreenState._onPipAction`:10716 | `case 'next':` → `case 'changed-next':` | killed; `onPipAction-next-label` |
| `onPipAction-play-break` | `_VideoPlayerScreenState._onPipAction`:10709 | `break;` → `<removed>` | equivalent; `onPipAction-play-break` |
| `onPipAction-pause-break` | `_VideoPlayerScreenState._onPipAction`:10709 | `break;` → `<removed>` | equivalent; `onPipAction-pause-break` |
| `onPipAction-toggle-break` | `_VideoPlayerScreenState._onPipAction`:10709 | `break;` → `<removed>` | equivalent; `onPipAction-toggle-break` |
| `onPipAction-next-break` | `_VideoPlayerScreenState._onPipAction`:10718 | `break;` → `<removed>` | equivalent; `onPipAction-next-break` |
| `pauseForBackground-opening-active` | `_VideoPlayerScreenState._pauseForBackground`:10747 | `_iptvStartOverActive &&` → `false &&` | killed; `pauseForBackground-opening-active` |
| `pauseForBackground-opening-intent` | `_VideoPlayerScreenState._pauseForBackground`:10748 | `_activeMediaShouldPlay &&` → `false &&` | killed; `pauseForBackground-opening-intent` |
| `pauseForBackground-opening-paused` | `_VideoPlayerScreenState._pauseForBackground`:10749 | `!_activeMediaUserPaused` → `false` | killed; `pauseForBackground-opening-paused` |
| `onPipAction-no-next-guard` | `_VideoPlayerScreenState._onPipAction`:10717 | `if (_hasAnyNext) _goToNextEpisode();` → `_goToNextEpisode();` | killed; `closure3-onPipAction-no-next-guard` |
| `onPipAction-default` | `_VideoPlayerScreenState._onPipAction`:10716 | `case 'next':         if (_hasAnyNext) _goToNextEpisode();         break;` → `case 'next':         if (_hasAnyNext) _goToNextEpisode();         break;       default: _togglePlay(` | killed; `onPipAction-default` |
| `retained-hidden-options` | `_VideoPlayerScreenState.initState`:1582 | `!widget.hideOptions` → `true` | killed; `retained-hidden-options` |
| `retained-support-accept` | `_VideoPlayerScreenState.initState`:1584 | `if (!mounted \|\| !ok) return;` → `if (!mounted) return;` | killed; `retained-support-accept` |
| `retained-pending-user-save` | `_VideoPlayerScreenState._togglePlay`:12658 | `unawaited(_saveResume(positionOverride: _position));` → `<removed>` | killed; `retained-pending-user-save` |
| `retained-support-mounted` | `_VideoPlayerScreenState.initState`:1584 | `if (!mounted \|\| !ok) return;` → `if (!ok) return;` | killed; `case-retained-support-mounted` |
| `onPipAction-null-input` | `_VideoPlayerScreenState._onPipAction`:10694 | `double.tryParse(action.substring(5))` → `double.tryParse(action.substring(5)) ?? 0.0` | killed; `case-onPipAction-null-input` |
| `enterPip-native-call` | `_VideoPlayerScreenState._enterPip`:10580 | `entered = await PipService.enterPip(         aspectWidth: player.state.width,         aspectHeight: ` → `entered = false;` | killed; `case-enterPip-native-call` |
| `restoreIosPipPlayer-native-orientation` | `_VideoPlayerScreenState._restoreIosPipPlayer`:10677 | `await SystemChrome.setPreferredOrientations(       _display.landscapeLocked           ? const [     ` → `await Future<void>.value();` | killed; `case-restoreIosPipPlayer-native-orientation` |
| `retained-registered-owner` | `_VideoPlayerScreenState.initState`:1585 | `PipService.attach(           this,` → `PipService.attach(           Object(),` | killed; `case-retained-registered-owner` |

### Equivalence resolutions

| Point | Source/runtime proof (tokens remain frozen) |
| --- | --- |
| `field-session` | State.didChangeDependencies synchronously assigns PlayerPipSession.of(context) before first build or any async support callback; the inactive initial session is never read or registered. |
| `enterPip-post-mounted` | The remaining isOwner(this) guard rejects disposal: dispose synchronously detaches the State before unmount, and late support registration itself checks mounted. No await in disposal between detach and unmount permits a false mounted/true owner result. |
| `enterPip-finally-mounted` | Same owner-implies-mounted invariant; both old State disposal and live owner replacement remain rejected by the remaining owner test. |
| `onPipModeChanged-mounted` | Only PipService invokes this callback: native mode dispatch and previousOnMode(false) on attach are synchronous. State disposal detaches its callbacks before unmount; no callback is captured across an await. |
| `restoreIosPipPlayer-mounted` | Initial restore invocation is synchronous through the currently registered onRestore callback, removed by State disposal. There is no async gap before this guard. |
| `restoreIosPipPlayer-owner` | PipService stores owner and onRestore together; synchronous dispatch invokes only that owner's callback. No await precedes the guard. The final post-await owner guard remains necessary and is independently killed. |
| `restoreIosPipPlayer-return-mounted` | The remaining isOwner(this) final guard implies mounted because dispose detaches before unmount, including disposal while orientation or endOfFrame is pending. |
| `onPipAction-mounted` | PipService dispatches onAction synchronously and clears it during State disposal before unmount; no retained/public action callback bypasses this registration. |
| `onPipAction-play-break` | Dart 3 implicitly exits a nonempty switch case. Removing its explicit terminal break does not fall through; SDK runtime proof and original replays pin all commands. |
| `onPipAction-pause-break` | Same implicit case-exit rule; independent original replay and runtime command trace. |
| `onPipAction-toggle-break` | Same implicit case-exit rule; independent original replay and runtime command trace. |
| `onPipAction-next-break` | Same rule, also final case with no statement after the switch. |

`switch-probe.log` verifies implicit case exit on the pinned Dart SDK; four independent original break-removal replays also pass. Ownership/mounted proofs rely on synchronous service dispatch, callback replacement and detach-before-unmount; they do not authorize guard removal, changed registration/disposal or combined mutants.

### Device-pending and early-window classification

| Point | Limitation / required original device scenario |
| --- | --- |
| `field-time` | Normal pause overwrites the implicit null; a first pause during real-Android renderer replacement can expose the initializer after recovery finishes. Non-equivalence is device-pending, not counted equivalent. |
| `enterPip-created` | Player replacement inside one live State requires real-Android renderer paths outside S2; route replacement changes State and does not establish this branch. |
| `enterPip-post-player` | Player replacement inside one live State requires real-Android renderer paths outside S2; route replacement changes State and does not establish this branch. |
| `enterPip-finally-player` | Player replacement inside one live State requires real-Android renderer paths outside S2; route replacement changes State and does not establish this branch. |
| `pauseForBackground-renderer` | Entry is real dart:io Platform.isAndroid in renderer fallback, deliberately outside approved S2; must not extend seam. |
| `pauseForBackground-renderer-latch` | Entry is real dart:io Platform.isAndroid in renderer fallback, deliberately outside approved S2; must not extend seam. |
| `pauseForBackground-renderer-pause` | Entry is real dart:io Platform.isAndroid in renderer fallback, deliberately outside approved S2; must not extend seam. |
| `resumeFromBackground-renderer` | Entry is real dart:io Platform.isAndroid in renderer fallback, deliberately outside approved S2; must not extend seam. |
| `resumeFromBackground-created` | Player replacement inside one live State requires real-Android renderer paths outside S2; route replacement changes State and does not establish this branch. |
| `resumeFromBackground-time-clear` | Player replacement inside one live State requires real-Android renderer paths outside S2; route replacement changes State and does not establish this branch. |

All five moved initializers are audited: starting/detached/initial second have early caller kills; nullable session is synchronously overwritten before any consumer; `_backgroundedAt` is overwritten by normal pause, but its first renderer-replacement pause window can expose its default and remains **non-equivalent/device-pending**. Native presentation (Android Home/return/actions; iOS AVKit start/stop/restore), real renderer recreation with/without a live instance, native recording clear-before-pause and native wake/power behavior remain on the device checklist. No new platform or clock seam is introduced.

### Per-case assertion witnesses

| New case | Original assertion-failing mutation run(s) |
| --- | --- |
| PiP Android readiness arms aspect, State identity and explicit entry payload | `armPipAutoEnter-enable`, `closure3-armPipAutoEnter-arm`, `closure3-retained-ready-arm` |
| PiP Android mode collapses chrome, cancels auto-hide and preserves active owner on exit | `onPipModeChanged-push`, `onPipModeChanged-active`, `retained-mode` |
| PiP Android hidden options registration stays absent supported=false | `retained-hidden-options` |
| PiP Android hidden options registration stays absent supported=true | `retained-hidden-options` |
| PiP Android action play pins action dispatch and invalid seek gates | `onPipAction-play`, `retained-action` |
| PiP Android action pause pins action dispatch and invalid seek gates | `onPipAction-pause`, `retained-action` |
| PiP Android action playpause pins action dispatch and invalid seek gates | `onPipAction-toggle`, `retained-action` |
| PiP Android action next pins action dispatch and invalid seek gates | `closure3-onPipAction-no-next-guard` |
| PiP Android action unknown pins action dispatch and invalid seek gates | `onPipAction-default` |
| PiP Android action seek:NaN pins action dispatch and invalid seek gates | `closure3-onPipAction-finite` |
| PiP Android action seek:Infinity pins action dispatch and invalid seek gates | `closure3-onPipAction-finite` |
| PiP Android action seek:oops pins action dispatch and invalid seek gates | `case-onPipAction-null-input` |
| PiP Android action seek pins action dispatch and invalid seek gates | `onPipAction-default`, `closure3-onPipAction-prefix` |
| PiP Android relative seek -10000.0 rounds milliseconds and clamps to the engine duration | `onPipAction-lower`, `onPipAction-seek` |
| PiP Android relative seek -0.2506 rounds milliseconds and clamps to the engine duration | `onPipAction-seek`, `onPipAction-position-unit`, `closure3-onPipAction-parse` |
| PiP Android relative seek 12.3456 rounds milliseconds and clamps to the engine duration | `onPipAction-round`, `onPipAction-seek`, `onPipAction-position-unit` |
| PiP Android relative seek 10000.0 rounds milliseconds and clamps to the engine duration | `onPipAction-upper`, `onPipAction-seek`, `onPipAction-position-unit` |
| PiP Android lost owner prevents entry, auto-enter and playing state pushes | `pushPipState-owner`, `closure3-armPipAutoEnter-owner` |
| PiP background cancels held Start Over probe while user-paused=false without hiding its feedback | `pauseForBackground-cancel`, `pauseForBackground-feedback` |
| PiP background cancels held Start Over probe while user-paused=true without hiding its feedback | `pauseForBackground-cancel`, `pauseForBackground-feedback` |
| PiP background during held playlist opening latches playing intent and pauses its late playing event | `pauseForBackground-transition`, `onPipAction-next-label`, `closure3-onPipAction-next` |
| PiP Start Over held open arms background intent even with user-paused=false before the new playing event | `case-pause-primary-latch` |
| PiP Start Over held open arms background intent even with user-paused=true before the new playing event | `pauseForBackground-opening-intent`, `pauseForBackground-opening-paused`, `case-pause-primary-latch` |
| PiP held support across dispose preserves original late registration | `case-retained-support-mounted` |
| PiP held support across owner preserves original late registration | `retained-support-arm` |
| PiP held support across profile preserves original late registration | `retained-support-arm` |
| PiP Android resolved support=false controls public entry availability | `retained-support-accept` |
| PiP Android resolved support=true controls public entry availability | `case-retained-registered-owner` |
| PiP iOS held handle across real route replacement preserves handles and wake exemption | `case-onPipModeChanged-park` |
| PiP iOS held subtitle across real route replacement preserves handles and wake exemption | `case-onPipModeChanged-park` |
| PiP iOS held entry across real route replacement preserves handles and wake exemption | `case-onPipModeChanged-park` |
| PiP iOS held orientation across real route replacement preserves handles and wake exemption | `case-onPipModeChanged-park` |
| PiP held support across real route replacement cannot reclaim the fresh State or handle | `closure3-retained-support-mounted` |
| PiP iOS entry prepares native subtitles once, sends its distinct handle and leaves auto-enter unarmed | `retained-subtitle-starting`, `retained-controls`, `enterPip-finally-subtitle` |
| PiP iOS real route parks and restores the same player with landscape=true orientation and native visibility | `retained-mode`, `retained-restore`, `closure3-restoreIosPipPlayer-detached` |
| PiP iOS real route parks and restores the same player with landscape=false orientation and native visibility | `retained-mode`, `retained-restore`, `closure3-restoreIosPipPlayer-detached` |
| PiP iOS repeated true mode while parked keeps the session and dismissal completes disposal | `onPipModeChanged-park`, `onPipModeChanged-close`, `onPipModeChanged-close-branch` |
| PiP iOS timeline pushes once per changed second including the initial zero second | `retained-second-read`, `retained-second-write`, `retained-position-push` |
| PiP iOS active window and a starting entry suppress background pause and catchup cancellation | `pauseForBackground-pip` |
| PiP iOS lost owner rejects a saved entry before handle delivery or starting subtitle suppression | `closure3-enterPip-owner` |
| PiP lifecycle Android valid transitions pause only at paused and clear the latch before play without saving | `resumeFromBackground-play`, `retained-pause`, `retained-resume` |
| PiP lifecycle iOS valid transitions pause only at paused and clear the latch before play without saving | `resumeFromBackground-play`, `retained-pause`, `retained-resume` |
| PiP lifecycle preserves a user pause and its real held resume write across background and foreground | `resumeFromBackground-latch`, `retained-pending-user-save` |
| PiP lifecycle resume may play before an older background pause completes and the late pause wins | `case-pause-primary-latch` |
| PiP lifecycle rejected background pause remains uncaught and resume still plays once | `case-pause-primary-latch` |
| PiP lifecycle sleep stop between background and foreground suppresses automatic play | `resumeFromBackground-sleep` |
| PiP pending user-pause save across profile and lifecycle writes its captured physical profile once | `retained-pending-user-save` |
| PiP pending user-pause save across dispose and lifecycle writes its captured physical profile once | `retained-pending-user-save` |
| PiP early callbacks while a prior output lease is held ignore actions and do not latch the first background open | `closure3-onPipAction-created` |
| PiP early next-key transition before output creation still ignores a synchronous background callback | `closure3-pauseForBackground-created` |
| PiP seek fans out to Trakt Simkl MDBList in order with the exact rounded target | `onPipAction-simkl`, `onPipAction-mdblist`, `onPipAction-order` |
| PiP Android native aspect payload width=0 height=0 retains zero fallback | `armPipAutoEnter-enable` |
| PiP Android native aspect payload width=null height=null retains zero fallback | `armPipAutoEnter-enable`, `pushPipState-width-zero`, `pushPipState-height-zero` |
| PiP Android native aspect payload width=1920 height=800 retains zero fallback | `armPipAutoEnter-enable`, `pushPipState-width`, `pushPipState-height` |
| PiP iOS plain screen has no session yet restore returns false without platform requests | `restoreIosPipPlayer-session` |
| PiP desktop predicate leaves State lifecycle pause and resume inactive | `pauseForBackground-mobile` |
| PiP play and pause commands are idempotent at the matching playing state | `closure3-onPipAction-play-gate`, `closure3-onPipAction-pause-gate`, `final-retained-playing-push` |
| PiP early audio setup uses false starting and detached defaults before open or readiness | `field-starting`, `field-detached`, `retained-controls` |
| PiP live background longer than thirty real seconds retunes once instead of playing stale buffer | `resumeFromBackground-retry`, `closure3-resumeFromBackground-absent`, `closure3-resumeFromBackground-source` |
| PiP iOS held handle across dispose preserves original entry and finalization boundaries | `case-enterPip-handle` |
| PiP iOS held handle across owner preserves original entry and finalization boundaries | `enterPip-post-owner` |
| PiP iOS held handle across profile preserves original entry and finalization boundaries | `case-enterPip-handle` |
| PiP iOS held subtitle across dispose preserves original entry and finalization boundaries | `case-enterPip-subtitle` |
| PiP iOS held subtitle across owner preserves original entry and finalization boundaries | `enterPip-finally-owner` |
| PiP iOS held subtitle across profile preserves original entry and finalization boundaries | `case-enterPip-subtitle` |
| PiP iOS held entry across dispose preserves original entry and finalization boundaries | `case-enterPip-native-call` |
| PiP iOS held entry across owner preserves original entry and finalization boundaries | `case-enterPip-native-call` |
| PiP iOS held entry across profile preserves original entry and finalization boundaries | `case-enterPip-native-call` |
| PiP iOS restore orientation held across dispose continues platform writes then checks State ownership | `case-restoreIosPipPlayer-orientation` |
| PiP iOS restore orientation held across owner continues platform writes then checks State ownership | `restoreIosPipPlayer-return-owner` |
| PiP iOS restore orientation held across profile continues platform writes then checks State ownership | `case-restoreIosPipPlayer-orientation` |
| PiP iOS starting handle prevents duplicate entries and background pauses until completion | `field-starting`, `enterPip-starting`, `pauseForBackground-pip` |
| PiP iOS handle rejection resets starting state and displays the original retry message | `enterPip-failure`, `enterPip-toast`, `enterPip-entered-default` |
| PiP iOS subtitle rejection resets starting state and displays the original retry message | `case-enterPip-failure` |
| PiP iOS entry rejection resets starting state and displays the original retry message | `retained-controls` |
| PiP failed iOS entry while background pause is held invokes the State fallback before retry toast and resume | `enterPip-paused`, `enterPip-pause`, `retained-controls` |
| PiP restore waits for the frame and observes owner replacement in that frame | `restoreIosPipPlayer-frame` |
| PiP rejected restore orientation propagates its channel error after reattaching and before immersive mode | `case-restoreIosPipPlayer-native-orientation` |
| PiP background cancels an active live recovery and clears its reconnect pill before resuming | `closure3-pauseForBackground-recovery`, `closure3-pauseForBackground-reconnect` |
| PiP iOS starting entry hides Flutter subtitles and keeps native subtitles during a playlist open | `enterPip-clear`, `closure3-retained-open-starting`, `closure3-retained-view-starting` |
| PiP parked next episode completes its original route result without reopening or returning fullscreen | `retained-result-park`, `retained-result-close` |
| PiP scoped State disposal completes its session while the hosting route remains present | `closure3-retained-dispose-close` |
| PiP wakelock follows initial acquisition, playing and pause, while buffering does not release it | `sync-wake`, `retained-playing-wake` |
| PiP wakelock independent owner prevents a pause or disposal release until that owner leaves | `wake-independent-owner` |
| PiP wakelock held first toggle samples latest queued playback requests after rapid pause play and disposal | `sync-wake`, `wake-latest-queue` |
| PiP wakelock native rejection is swallowed and subsequent queued requests still complete | `sync-wake`, `retained-playing-wake`, `wake-native-rejection` |
| PiP wakelock EOF playing-false=false releases only on the playing stream | `sync-wake` |
| PiP wakelock EOF playing-false=true releases only on the playing stream | `sync-wake`, `retained-playing-wake` |
| PiP detached owner handoff keeps playback wake requested when the old parked session closes | `onPipModeChanged-detached`, `retained-dispose-detached` |
| PiP replaced parked route keeps wake for a hidden-options incoming player while its setup is held | `retained-dispose-replaced` |

### Contracts, baseline and preserved findings

`contract-results.json`: `wake-independent-owner`, `wake-latest-queue`, `wake-native-rejection` and `pending-fixture-protocol` all KILLED by assertions. The native rejection case explicitly rejects a queued public display-control request so Video’s own exception handler cannot conceal the service contract. The other owner keeps wake after player pause/disposal; queued writes sample the latest intent at execution.

Pristine S2 full-suite `original-suite.jsonl` reproduced an unrelated pre-existing guide/profile race in the MDBList outgoing checkpoint test. Three unchanged original isolated replays pass; the fixture joins Trakt/Simkl/MDBList public guide refreshes **before** starting the tested held POST. Original names/assertions are retained (`pending-token-proof.json`); the denominator mutation independently kills its existing protocol assertion. No allowlist or application fix. Complete stabilized original baseline: 13,296 success / 13 failure / 28 load error / 20 skip, exactly the five S2 additions versus P7. Final full suite: **13,386 success / 13 failure / 28 load error / 20 skip**. Official and strict identity comparisons PASS: exactly 90 passing additions, no changed, missing, fixed or skipped old identity. Tested inputs stayed stable during the completed run. The sole later test-input change removes one duplicate analyzer-ignore comment; `post-suite-input-proof.json` proves the exact byte delta leaves all executable bytes unchanged, and final targeted analysis is clean. `coverage.json`, `final-audit.log` and `completion.json` revalidate the selected complete mutation logs, baseline and unchanged original application.

As-is findings: backgrounding before output creation does not latch the first open; a pending old background pause can finish after resume and win; the old user-pause save writes its captured physical profile, with no new background save. A held iOS subtitle preparation can start entry after State/owner loss; after real replacement its late service handle can let an old-handle action pause the fresh player until the fresh entry rebases it. Restore continues platform writes across handoff before its final State-owner check; profile changes do not cancel these State-owned operations. These are preserved and recorded in Follow-ups.

Development controls with wrong fixture assumptions, an incomplete loader/promotion mutant, error-only removals and a failed control are archived and uncredited. Guide close itself cancels replay; final test leaves it open during backgrounding. Nullable-promotion mutant replaced by a flow-valid `false` conjunction. Two fixture-copy commands used the detached cwd and raised SameFileError; corrected copies and complete controls are archived. Final characterization files format and analyze cleanly, size/architecture pass; all Step-T historical/self/S/S2/analyzer proofs remain valid because tooling and application are unchanged. Dependency files unchanged; no production move, build/run/install, device command, real network, push, merge or branch switch. Stop at Step 0.

## Phase 8 independent sample and Step-0b closure (2026-10-13)

Claude's independent sample at `6785b4985` (application identical to S2)
killed **18/20 valid mutations (90%)**. Evidence:
`p8/claude-sample/{p8-claude-muts.json,p8-claude-run.log,results.json}` and
per-mutation logs. No compile-error exclusion or equivalence credit.

| Sample points | Independent result | Addendum evidence |
| --- | --- | --- |
| k1, k3–k18, k20 | 18 assertion kills | Independent per-mutation logs |
| k19: live-rejoin threshold 30 → 3 seconds | Survived sample; assertion killed by addendum | `step0b/k19-results.json`, `k19.jsonl`, `k19.patch`; original detached `6785b4985` |
| k2: post-handle captured-player identity guard removed | Survived; prerequisite unresolved | `step0b/k2-reachability.json`; no assertion-kill credit |

The new public-lifecycle case waits five real seconds after backgrounding a live
IPTV channel, then asserts one existing open, exactly one in-buffer play, no
`lifecycle-rejoin` diagnostic, the unchanged channel and no uncaught error. It
checks that the observed wait lies strictly between 3 and 30 seconds. The
existing >30-second case remains and asserts a retune, no direct play and the
exact rejoin diagnostic. The complete projection control passes; the new case
passes in the detached original and assertion-fails with k19 there. No clock
seam or production change. This adds one case and one literal mutation witness
to the `_resumeFromBackground` coverage row; the original upper-threshold
witness (30 → 300) remains valid.

k2 requires replacement **inside the same State** while handle delivery is
held. The only player assignments are initial setup and
`_fallbackExplicitRendererToAutomatic`; the latter's eligibility uses real
`Platform.isAndroid`, outside S2. Renderer settings loading is likewise guarded
by real Android. Ordinary media/playlist updates reuse the same instance;
route replacement changes State/owner and is rejected by the remaining owner
guard, so it cannot witness this mutation. No private State call, duplicate
`initState`, reflection or new application predicate has been used to manufacture
the condition. The separately reviewed seam prerequisite is pending; k2 retains
its existing device-pending classification rather than being reported killed or
equivalent. Step 1 has not started.

The fresh completed addendum suite records **13,387 successes / 13 failures /
28 load errors / 20 skips**. Official and strict comparisons against Step 0
PASS: exactly one passing addition, no changed/missing/fixed/newly skipped old
identity. Test inputs and tracked tree stayed stable throughout the run.
Projection format/analyze and diff checks PASS. Evidence:
`step0b/{projection-control.jsonl,control.jsonl,k19-results.json,final-suite.jsonl,
final-suite.env.json,baseline-compare.log,baseline-strict.json,coverage.json}`.
The un-applied two-site prerequisite proposal is
`step0b/seam-prerequisite-proposal.patch`; it changes neither hook defaults nor
installation and is not credited as an original behavior witness. k2, the
production move and gate remain pending the seam direction.

## Phase 8 S2b — approved renderer predicate seam extension (2026-10-13)

Claude, as plan owner, approved the two-site extension as a separate checkpoint:
k2 requires same-State player replacement, available only through Android
renderer fallback; the later player-engine phase also needs these predicates
covered. The Characterization harness and Phase-8 S2/S2b decision record this
rationale. Application diff from `652def541` is exactly two substitutions:

| Declaration | Exact predicate patch, once | Independent site negatives |
| --- | --- | --- |
| `_initializePlayer` | `if (Platform.isAndroid && !PlatformUtil.isAndroidTvCached)` → `if (VpS2Hooks.isAndroid && !PlatformUtil.isAndroidTvCached)` | Wrong predicate, bypassed override, twice, operand order, changed TV predicate |
| `_canFallbackExplicitRenderer` | `isAndroid: Platform.isAndroid` → `isAndroid: VpS2Hooks.isAndroid` | Wrong predicate, bypassed override, twice, argument order, changed TV predicate |

The scoped token patches keep both other Android reads in `_initializePlayer`
unchanged. S2's existing getter defaults, callback evaluation, installer,
release/profile rejection, assert-only assignment and compile-time flag are
byte/token-identical. No new hook/installer. The manifest remains a checkpoint:
817 exhaustive original spans, 11 patched declarations / 13 counted patches /
17 predicate occurrences. All nine accepted S2 declarations and their patches
are preserved; the original S interception proof remains unchanged. Independent
site guards pin one getter read in the original short-circuit/named-argument
order, separately from the move comparison core. The frozen getter evaluates
the original native predicate once when no override is installed.

Evidence under `p8/s2b/`: S and S2/S2b self-proofs, current seam checker and
historical S2 checker `--at 21b19c944` PASS, each with a fresh isolated copied
parser package and deleted copied kernels. The 23 independent negatives include
the original 13 plus five per new site. Existing S/S2 guard tests pass in both
flag modes (7 cases each), including native defaults, live once-only overrides
and flag-disabled installation rejection. Their names and prior assertions
remain; the source guard additionally requires both new negative sets.

Targeted root analyzer retains **98 scoped diagnostics / zero additions** by
identity and multiplicity; comparator self-tests PASS. Updated guard test
analysis is clean. Dart format and idempotence, size, architecture and diff
checks PASS. Initial manifest drafts with a broad three-occurrence pattern and
missing patch metadata were rejected, archived separately and uncredited;
final scoped patches include the required reason/test fields. No app bug fix,
production move, k2 test, CI transition, pubspec change, real network or device
action. S2b stops for independent review. After acceptance, refresh the draft
P8 manifest/probe against the S2b original before k2 and production work; the
old S2 Step-T materialization is not a current-tree proof of this extension.

## Phase 8 S2b original — k2 and renderer reachability closure (2026-10-13)

Fresh independent review `vp-rev8s2b`: no P1/P2/P3. S2b `866cbaf03` is
the behavior ORIGINAL. The held iOS-style entry uses S/S2/S2b, the real controls
callback, real player-error subscription and renderer fallback inside the same
State. It asserts unchanged State/owner, old disposal, distinct handles, the new
open and persisted Automatic renderer. Only after replacement setup finishes
does it release the old handle; subtitle writes on both players, state pushes
and native entry counts stay unchanged. Removing the post-handle player check
produces an assertion failure on the detached original; unmodified control
passes (`p8/k2/{results.json,control.jsonl,k2.jsonl,k2.patch}`). No private calls.

S2b also makes the old deferred renderer points reachable. Four registered
caller tests cover a captured entry during disposal, backgrounding before and
after replacement creation, foregrounding while native audio configuration is
held, first live-buffer resume and reuse of a consumed long-absence timestamp.
Assertions are evaluated while the specified disposal/audio boundary is held.
The renderer gap removes the Video subtree: no extra old-player pause; a created
player receives the State's one pause before setup completes. This is pinned
as-is rather than assuming the two pauses of an ordinary ready screen.

| Previously deferred point | Final S2b result / original witness |
| --- | --- |
| `enterPip-post-player` | killed; `k2/k2` |
| `enterPip-created` | killed; `k2/renderer-mutations/enterPip-created` |
| `enterPip-finally-player` | killed; `k2/renderer-mutations/enterPip-finally-player` |
| `field-time` | killed; `k2/renderer-mutations/field-time` |
| `pauseForBackground-renderer` | killed; `k2/renderer-mutations/pauseForBackground-renderer` |
| `pauseForBackground-renderer-latch` | killed; `k2/renderer-mutations/pauseForBackground-renderer-latch` |
| `pauseForBackground-renderer-pause` | killed; `k2/renderer-mutations/pauseForBackground-renderer-pause` |
| `resumeFromBackground-renderer` | killed; `k2/renderer-mutations/resumeFromBackground-renderer` |
| `resumeFromBackground-time-clear` | killed; `k2/renderer-mutations/resumeFromBackground-time-clear` |
| `resumeFromBackground-created` | equivalent; `k2/renderer-mutations/resumeFromBackground-created` |

The resume-created/mounted guard is redundant on current registered lifecycle
callers: the only absent-player states are initial setup (latch false) and
renderer fallback (preceding guard returns); fallback restores/creates the
player before clearing its flag. Disposal unregisters the synchronous listener
before unmount, with no awaited/captured resume callback or synchronous element
unmount during the current application's lifecycle dispatch. The complete
original renderer/held-entry replay passes after removing that guard. Full
source reasoning and SDK path: `resume-created-equivalence.json`. It remains
frozen in production; no removal is authorized by this classification.

Updated canonical matrix: **154 assertion kills / 13 equivalences / 167 points**;
the earlier 327-site inventory and 22 retained occurrence ledger still apply,
with these ten historical S2 classifications superseded. **96 behavior cases in
11 files**, each with an original assertion witness. Native presentation, real
recording tee ordering, and native power/decoder integration remain genuine
device checklist work; no renderer statement is mislabeled device-only after
S2b. k19's lower-threshold witness remains recorded alongside its existing
upper-threshold witness; independent sample is now fully closed (original
18/20, both survivors assertion-proven), without claiming a new independent
sample run. `coverage.json` links the canonical and per-case witnesses.

The draft move manifest and analyzer inventory were refreshed against S2b,
materialized in `p8/refresh/` only. 14 moves, 22 retained occurrences, seven
State-owner substitutions and earlier destinations compare with zero diffs.
Optional-comma and format idempotence proof PASS; root/strict/probe 98/170/99,
prior mappings preserved. New renderer file registered in the existing flag
command list. Rejected startup/package setup controls and initial fixture count
assumptions are archived and uncredited; final original controls and all credited
mutation logs complete without load errors. Test analysis/format clean. Full
additions-only baseline follows before production moves.

## Phase 8 Step 1 production creation (2026-10-13)

Addendum `13df9a261` full baseline completes at 13,392 success / 13 failure /
28 load error / 20 skip: exactly five passing additions versus the prior k19
baseline; no changed, missing, fixed or newly skipped old identity. Both
identity comparisons PASS, inputs stable. S2b remains the behavior original.

The applied P8 manifest moves 14 declarations into the 318-line
`vp_pip_lifecycle.dart`; eager State constructor assignment after completion,
narrow live Host/adapter, seven State-owner substitutions and all 22 retained
occurrences compare with zero differences. The onPause closure remains in the
facade, recording teardown before its substituted inner pause call. Disposal
statements keep their original position. Five initializers and constructor
remain inert; callbacks/visibility registration and borrowed state stay owned
by State. No earlier destination changes. The optional-comma proof and
idempotence archive every permitted format delta; zero format diagnostics.

CI current/self-test and both analyzer inputs use P8; named P1–P7 historical
checks remain, S and S2/S2b proofs enabled. Existing feature-directory format/
analyze coverage includes the new file. The eleven behavior files include
the registered renderer file; existing harness commands retain the compile
flag. Theme manifest, rendered set and all three source-guard path lists gain
the new destination. There is no additional direct anchor in another source
test for these moved declarations; the validating reader continues to follow
the applied manifest. No assertion deleted. Facade cap lowered 17,004 → 16,829.

Focused moved PiP/lifecycle/wakelock/renderer, seam and theme guards pass
111/111. Current checker, format and architecture PASS. Destination diagnostics
are three recorded infos (two original brace infos, one receiver-induced async
context info); no new warning allowlist entry. Evidence `p8/step1/`; full
clean-tree suite, all manifest checks and both release builds follow at the
gate. No bug fix or dependency change.

## Phase 8 clean-tree gate (2026-10-13)

Production revision `901d08edd`, against addendum original baseline
`13df9a261` (S2b application `866cbaf03`): complete full suite
13,392 success / 13 failure / 28 load error / 20 skip. Official and strict
identity comparisons PASS: no changed, added, missing or newly skipped case;
identical SDK, clean stable tested tree. No flake or fixture change.

All 38 manifest/history/seam jobs PASS, including every existing Dart
manifest self-test, P8 self-test/current, Kotlin's 597 tests, P1–P7 named
historical revisions and S/S2/S2b proofs. Format, size/architecture and real
architecture negatives PASS. Analyzer comparator: 99 scoped diagnostics,
zero additions; complete CI scope has the same scoped diagnostics and its
54 recorded pre-existing warnings pass the shared allowlist. Both nice-19
release builds (APK and macOS, `--no-pub`) PASS. Evidence `p8/gate/`, with
`completion.json`, full identity outcomes, commands, isolated parser audit
and artifact hashes. The facade remains 16,829 lines; destination 318.

The size updater's removed provenance comments are restored with the P8
ratchet note. Invalid supplemental allowlist inputs (narrow log/unexpanded
glob) are archived uncredited; corrected CI scope passes. Gate commit
changes only documentation/size-baseline comments. Native Android/iOS PiP
presentation/restoration, real recording teardown and wake/decoder power
checks remain device-pending; M1 is after merge. No application bug fix,
allowance, dependency change, live application request, run/install/device
command or push/merge/branch switch. Stop for independent Phase-8 review.

## Integration milestone M1 (2026-10-13)

The one new scenario uses one State/player for two episodes with local progress
ownership and all three enabled synthetic-credential scrobble targets. It
observes synchronous tracker order through timer ownership and independently
checks asynchronous protocol delivery, seek, persisted speed/restore, completion
threshold/one-shot writes, EOF sleep suppression, S2 background/foreground,
explicit play and episode reset. Final test bytes pass unchanged on original
`13df9a261` lib/ and merged `0df6ccd4e`. No production code changes.

| Original mutation witness | Phase | Assertion pinned | Result |
|---|---|---|---|
| `p2-eof-sleep-latch` | 2 retained EOF site | sleep stop forbids foreground play | killed |
| `p3-skip-fanout-order` | 3 | tracker timer-owner cancellation order | killed |
| `p4-resume-native-rate` | 4 retained resume site | saved 1.5x reaches incoming native rate | killed |
| `p5-trakt-seek-stop` | 5 | three stop protocols and exact progress | killed |
| `p6-mdblist-seek` | 6 | third tracker consumes the skip seek | killed |
| `p7-episode-one-shot-reset` | 7 | incoming episode marks after outgoing completion | killed |
| `p8-resume-sleep-guard` | 8 | sleep latch wins over lifecycle resume | killed |
| `p2-explicit-play-latch` | 2 retained play site | next foreground resumes after explicit play | killed |

Eight of eight valid mutations assertion-killed across seven phases; original
control and restored control pass. Final file hashes, complete JSON logs and
patches: `m1/scenario/`, `m1/mutations/`. No failed-load mutation credited.

A full-suite Simkl snapshot/profile SQLite lock was reproduced on unmodified
original, before a test-only registry-wait stabilization. The `incomingProfile`
helper now uses shared `finish()` while pending widget-zone transactions progress;
operation order/arguments, held readers/guide barriers and all test assertions
remain. Entire main test body byte-identical. Five final original 34-case
replays PASS; `m1/flake/` and `gate/fixture-note.md` archive diagnosis, assertion
proof and uncredited interrupted attempts. No production stale-result fix.

Final full suite vs Phase-8 gate is additions-only: 13,393 success / 13 failure /
28 load error / 20 skip, exactly one passing M1 addition and no changed/missing
old identity. Analyzer, format, size/architecture, all 38 mechanical jobs and
both release builds PASS; `m1/gate/completion.json`. Native PiP presentation,
recording and wake/decoder power checks remain device-pending. M1 complete.

## Phase 9 Step T — subtitle engine I (2026-10-13)

Original `bd671bd09` (M1), design parent `6e9b187c8`; draft
`dev/tool/dart_moves/vplayer_p9.json`. Evidence `p9/stepT/completion.json`
contains commands, results and initializer proofs; `probe/remeasured.json`
and `retained-ledger.json` re-measure the frozen names, not historical lines.
807 exhaustive spans, 21 moves (five inert fields, sixteen methods), 33 retained
occurrences, one combined bridge, exact 14-declaration Host/adapter and all
18 earlier destinations compare with zero differences. Settings, external path,
overlay flag and notifier stay State-owned. Each renderer/facade disposal
statement remains in position; the latter does not call the hide helper after
notifier disposal. Constructor appends after PiP, without a Host read.

Every existing Dart-manifest self-test, the complete P9 real/global self-test,
807-span original self-compare, Kotlin's 597 tests, named P1–P8 historical
checks and S/S2/S2b proofs PASS (38 jobs). All parser packages isolated with
copied kernels deleted. One initial fixture needle omitted a scanner-rendered
space in `mk . Player`; corrected only the fixture, complete P9 rerun PASS.
Analyzer root/strict/probe 99/171/104; earlier mappings preserved, no new
async-context identity. Three unused facade imports induced by the planned
move and two new directive infos are recorded in the probe inventory. No
allowlist change yet. Formatting preserves identities exactly (104), adds
zero diagnostics, records every AST optional-comma site and is idempotent.
Application, dependencies, size ratchet and CI current selection unchanged;
production application of this draft belongs to Step 1, after characterization.


## Phase 9 Step 0 — original subtitle engine I

Original application `bd671bd09`; tooling checkpoint `9d36d7c83`.
One production engine is activated through public subtitle selection, parses
fixture SRT, observes deterministic audio metadata at its actual property
fallback, and returns actual isolate-computed alignments. File-filter install
and removal barriers exercise the real lifecycle queue separately. No fake
engine, synthetic notices, private State calls or source-text behaviour tests.

| Original declaration | Behaviour through original caller |
|---|---|
| `_subtitleAutoSyncEnabled` | stored enablement both ways; early defaults overwrite audit |
| `_subtitleAutoSync` | selection before installation, identical-path early return, replacement clear gap, late old callbacks |
| `_autoSyncWindowActive` | cold late-offset/reset case; manual hide then suppressed new selection; all notice states |
| `_autoSyncPillHold` | exact 2400 ms result, rearm cancellation, manual/off cancellation and dispose |
| `_autoSyncPillPhaseTimer` | exact 5 s announcement, fresh listening cancellation and dispose |
| `_installSubtitleAutoSyncForPlayer` | enabled/disabled, nonnative, exact diagnostic, desktop raw-Android negative; engine live readers |
| `_disposeSubtitleAutoSync` | held installation/removal, renderer clear before new audio configuration and old player/lease release |
| `_applyAutoSubtitleSyncOffset` | actual 1869 ms result/native/session/UI rebuild; cumulative verification clamp beyond +1 hour (m4); unawaited native rejection remains outside persistence catch |
| `_showSubtitleAutoSyncNotice` | listening/checking/still-listening/synced/failed/silent-resynced, exact diagnostic messages |
| `_openAutoSyncPillWindow` | 5 s announce boundary, fresh subtitle/audio restart during old deadlines |
| `_showAutoSyncPillResult` | actual computed verdicts, 2400 ms hold and retained 350 ms fade |
| `_hideAutoSyncPill` | off/manual/renderer cleanup, fresh selection cannot inherit old callback |
| `_setActiveExternalSubtitlePath` | no-engine early path, same-path guard, null deactivation, automatic source priority, foreign-audio retirement and decoder rollback |
| `_loadSubtitleSettings` | actual migration/style, positive and negative late session offset before engine (m14), null model before returned snapshot, disposed rejection, accepted stale profile snapshot, font/prefs races |
| `_onSubtitleStyleChanged` | appearance rendering, equal-offset preservation, changed-offset generation retirement, saved callback after disposal |
| `_applySubtitleSyncOffset` | exact three-decimal signed seconds, native/nonnative, propagated native errors |
| `_resetSubtitleSyncOffset` | physical session-only reset; UI/native reset via track, content and menu callers |
| `_showSyncOverlayPanel` | sync menu action, transport opacity, TV first key/focus release |
| `_hideSyncOverlay` | overlay dismiss, Escape and TV PopScope route Back; playback stays mounted |
| `_buildSyncOverlay` | external path snapshot, live player position, late callbacks across dismissal/replacement/disposal, null settings and manual feedback during alignment |
| `_buildSliderSyncOverlay` | signed offset, both clamp boundaries, null model default, late callbacks, TV repeats and stable element |

Original behaviours intentionally retained: session offset is a singleton and
an overlapping route resets it while an outgoing model remains nonzero; stale
mounted settings snapshots cross profile handoff; font loading can read incoming
prefs or throw after reset; stale prefs init can overwrite the shared cache with
a stale wrapper. Saved line callbacks can affect a replacement player; after
disposal their service write precedes a disposed-notifier error/native call.
Quiet saved stepper callbacks can still write native properties after disposal.
Native property rejection propagates separately while session/model/verdict
continue. Retired seek results can leave Checking until a later event.

Device/dormant limits: no real native audio DSP/decoded timing claim; Android
compressed passthrough stop/PCM rearm and web/native-platform support predicates
are not overridden by S2. The constant unified-menu early return makes the legacy
TracksSheet branch and five ledger occurrences dormant. Existing native widgets,
keys and retained factories keep their original identity. M2 remains later work.

The exhaustive AST inventory has **190 statement/branch/literal/return/case
sites over all 21 declarations**. Its 170 canonical mutation candidates are
**151 assertion-killed, 12 replayed equivalents, two raw-Android device-pending,
two dormant persistence-catch diagnostics and three compiler-invalid operator
candidates**. The invalid nullable-flow reversals are not credited; their
parent null/path branches and snapshots have separate valid kills. Null/case
AST sites are grouped with their enclosing assignment/branch/dispatch; all
five enum notice routes run through the real engine. Three nullable fields
have no alternative inert non-null constant; their creation/use/disposal
protocols are executable, and T freezes their exact initializers.

All **26 reachable retained occurrences** have individual assertion-failing
mutations. Five legacy-sheet occurrences are dead behind
`kUnifiedPlayerMenuEnabled`; two raw-Android passthrough occurrences remain
pending. Three additional live engine readers (position, playing, offset),
the disposed settings guard and uncaught storage-error propagation have
independent kills. Every one of the **70 final new tests** has a completed
assertion-failing original witness with matching final test-file hashes.

Evidence: `p9/step0/coverage.json`, AST/retained inventories, source snapshots,
per-mutation patches/JSON/stderr, controls and input hashes. The original and
restored controls pass; detached application code is restored to `bd671bd09`.
No compile/load failure, timeout, interruption or error without an assertion
is counted. Earlier exploratory input/logs are retained with their actual
status, not promoted to final evidence. The final corpus uses shared H support
without edits; no production code, pubspec, CI current selection or ratchet edit.

Two preliminary focused commands inherited the shared fixture's P8 runtime
fallback; their exact birthtime-matched fixture directories were moved into P9
and those runs excluded. Accepted controls/replays/full suite set the P9 root
explicitly. An early new-case expected offset was corrected to the deterministic
original result (2.121 s after re-arm), and pointer checks wait the recognizer's
300 ms deadline. Assertions were not loosened. Two throwing-return variants
timed out and are excluded; finite unwanted-pill exit variants supply actual
assertion kills instead. No application fix or new seam.

### Retained-occurrence coverage

| Frozen occurrence | Original declaration / line | Caller mutation / classification | Witness |
|---|---|---|---|
| `r01` `_loadSubtitleSettings` | `initState`:1622 | assertion killed | subtitle overlapping route resets singleton offset while the outgoing route retains its model |
| `r02` `_subtitleAutoSync` | `_applyPassthroughFlip`:2130 | device-pending | Live Android passthrough guards are raw Platform predicates, outside S2. |
| `r03` `_subtitleAutoSync` | `_applyPassthroughFlip`:2147 | device-pending | Live Android passthrough guards are raw Platform predicates, outside S2. |
| `r04` `_installSubtitleAutoSyncForPlayer` | `_initializePlayer`:2430 | assertion killed | subtitle off then new selection cannot inherit an old announcement hide |
| `r05` `_subtitleAutoSync` | `_bindPlayerInstanceSubscriptions`:2870 | assertion killed | subtitle held alignment handles the retained seek jump subscription |
| `r06` `_subtitleAutoSyncEnabled` | `_bindPlayerInstanceSubscriptions`:2886 | assertion killed | subtitle held alignment handles the retained new audio subscription |
| `r07` `_subtitleAutoSync` | `_bindPlayerInstanceSubscriptions`:2897 | assertion killed | subtitle held alignment handles the retained new audio subscription |
| `r08` `_disposeSubtitleAutoSync` | `_fallbackExplicitRendererToAutomatic`:3404 | assertion killed | subtitle replacement clears the disposed engine before incoming audio setup and a saved selection |
| `r09` `_installSubtitleAutoSyncForPlayer` | `_fallbackExplicitRendererToAutomatic`:3439 | assertion killed | subtitle replacement clears the disposed engine before incoming audio setup and a saved selection |
| `r10` `_setActiveExternalSubtitlePath` | `_handleSubtitleApplyFailure`:4174 | assertion killed | subtitle late decoder rollback restores the previous external path and reactivates the real engine |
| `r11` `_subtitleAutoSyncEnabled` | `_loadPlayerDefaults`:5481 | assertion killed | subtitle rollback held through disposal sees the cleared engine before the mounted UI guard |
| `r12` `_subtitleAutoSyncEnabled` | `_loadPlayerDefaults`:5484 | assertion killed | subtitle stored enablement false gates actual installation and selection |
| `r13` `_autoSyncPillHold` | `dispose`:10574 | assertion killed | subtitle dispose cancels result hold before notifier disposal |
| `r14` `_autoSyncPillPhaseTimer` | `dispose`:10575 | assertion killed | subtitle dispose cancels announcement before notifier disposal |
| `r15` `_subtitleAutoSync` | `dispose`:10723 | assertion killed | subtitle pending filter removal across disposal preserves the lifecycle queue |
| `r16` `_subtitleAutoSync` | `dispose`:10724 | assertion killed | subtitle rollback held through disposal sees the cleared engine before the mounted UI guard |
| `r17` `_hideSyncOverlay` | `_closeTopPlayerOverlay`:11938 | assertion killed | subtitle route Back dismisses the top sync overlay before leaving playback |
| `r18` `_hideSyncOverlay` | `build`:13163 | assertion killed | subtitle TV Android TV first key repeat and Back retain overlay element |
| `r19` `_buildSyncOverlay` | `build`:14283 | assertion killed | subtitle early stepper reads zero while the original settings snapshot is suspended |
| `r20` `_setActiveExternalSubtitlePath` | `_showTracksSheet`:15102 | dormant | _showTracksSheet returns through the const unified menu before the legacy TracksSheet call. |
| `r21` `_resetSubtitleSyncOffset` | `_showTracksSheet`:15111 | dormant | _showTracksSheet returns through the const unified menu before the legacy TracksSheet call. |
| `r22` `_onSubtitleStyleChanged` | `_showTracksSheet`:15120 | dormant | _showTracksSheet returns through the const unified menu before the legacy TracksSheet call. |
| `r23` `_showSyncOverlayPanel` | `_showTracksSheet`:15121 | dormant | _showTracksSheet returns through the const unified menu before the legacy TracksSheet call. |
| `r24` `_setActiveExternalSubtitlePath` | `_menuApplyTrackChange`:15257 | assertion killed | subtitle off then new selection cannot inherit an old announcement hide |
| `r25` `_setActiveExternalSubtitlePath` | `_menuSelectAddonSubtitle`:15370 | assertion killed | subtitle off then new selection cannot inherit an old announcement hide |
| `r26` `_setActiveExternalSubtitlePath` | `_applyStremioSubtitleFromTracksSheet`:15406 | dormant | _showTracksSheet returns through the const unified menu before the legacy TracksSheet call. |
| `r27` `_resetSubtitleSyncOffset` | `_buildPlayerMenuPanel`:15458 | assertion killed | subtitle timing reset clears session and skips nonnative property |
| `r28` `_onSubtitleStyleChanged` | `_buildPlayerMenuPanel`:15475 | assertion killed | subtitle style callback renders appearance without restarting unchanged timing |
| `r29` `_showSyncOverlayPanel` | `_buildPlayerMenuPanel`:15476 | assertion killed | subtitle early stepper reads zero while the original settings snapshot is suspended |
| `r30` `_setActiveExternalSubtitlePath` | `_resetSubtitleState`:15519 | assertion killed | subtitle content replacement clears timing and path but a saved line callback targets the new playback |
| `r31` `_resetSubtitleSyncOffset` | `_resetSubtitleState`:15524 | assertion killed | subtitle content replacement clears timing and path but a saved line callback targets the new playback |
| `r32` `_setActiveExternalSubtitlePath` | `_refreshSubtitleAudioPolicy`:15826 | assertion killed | subtitle automatic source priority retires on preferred audio |
| `r33` `_setActiveExternalSubtitlePath` | `_applySubtitlePriorityUpdate`:16307 | assertion killed | subtitle automatic source priority activates the real engine through its retained caller |

### Mutation table

| Point | Original declaration / line | Before → after | Classification / evidence |
|---|---|---|---|
| `p001` | `_subtitleAutoSyncEnabled`:1330 | `false → true` | equivalent; `final-closure/p001` |
| `p002` | `_autoSyncWindowActive`:1337 | `false → true` | killed; `closure/p002` |
| `p003` | `_installSubtitleAutoSyncForPlayer`:1952 | `!_subtitleAutoSyncEnabled \|\| !PlatformUtil.supportsSubtitleAutoSync → false && (!_subtitleAutoSyncEnabled \|\| !PlatformUtil.supportsSubtitleAutoSync)` | killed; `sweep/p003` |
| `p004` | `_installSubtitleAutoSyncForPlayer`:1952 | `\|\| → &&` | killed; `sweep/p004` |
| `p005` | `_installSubtitleAutoSyncForPlayer`:1953 | `debugPrint(         'SubtitleAutoSync: not installing — enabled=$_subtitleAutoSyncEnabled '         'web=$kIsWeb platfor… → <removed>` | killed; `sweep/p005` |
| `p006` | `_installSubtitleAutoSyncForPlayer`:1954 | `'SubtitleAutoSync: not installing — enabled=$_subtitleAutoSyncEnabled ' → 'MUTSubtitleAutoSync: not installing — enabled=$_subtitleAutoSyncEnabled '` | killed; `sweep/p006` |
| `p007` | `_installSubtitleAutoSyncForPlayer`:1955 | `'web=$kIsWeb platform=${Platform.operatingSystem}' → 'MUTweb=$kIsWeb platform=${Platform.operatingSystem}'` | killed; `sweep/p007` |
| `p008` | `_installSubtitleAutoSyncForPlayer`:1957 | `return; → <removed>` | killed; `sweep/p008` |
| `p009` | `_installSubtitleAutoSyncForPlayer`:1959 | `final platform = player.platform; → final platform = null as mk.PlatformPlayer?;` | killed; `sweep/p009` |
| `p010` | `_installSubtitleAutoSyncForPlayer`:1960 | `platform is! mk.NativePlayer → platform is! mk.NativePlayer \|\| _subtitleAutoSyncEnabled` | killed; `final-closure/p010-valid` |
| `p011` | `_installSubtitleAutoSyncForPlayer`:1961 | `debugPrint(         'SubtitleAutoSync: not installing — player backend is not NativePlayer '         '(${platform.runtim… → <removed>` | killed; `closure/p011` |
| `p012` | `_installSubtitleAutoSyncForPlayer`:1962 | `'SubtitleAutoSync: not installing — player backend is not NativePlayer ' → "SubtitleAutoSync: not installing — player backend is not NativePlayer  mutant"` | killed; `closure/p012` |
| `p013` | `_installSubtitleAutoSyncForPlayer`:1963 | `'(${platform.runtimeType})' → 'MUT(${platform.runtimeType})'` | killed; `closure/p013` |
| `p014` | `_installSubtitleAutoSyncForPlayer`:1965 | `return; → return _openAutoSyncPillWindow();` | killed; `extra/p014-exit-effect` |
| `p015` | `_installSubtitleAutoSyncForPlayer`:1967 | `debugPrint(       'SubtitleAutoSync: controller installed '       '(passthrough=${!kIsWeb && Platform.isAndroid && _audi… → <removed>` | killed; `sweep/p015` |
| `p016` | `_installSubtitleAutoSyncForPlayer`:1968 | `'SubtitleAutoSync: controller installed ' → "SubtitleAutoSync: controller installed  mutant"` | killed; `sweep/p016` |
| `p017` | `_installSubtitleAutoSyncForPlayer`:1969 | `'(passthrough=${!kIsWeb && Platform.isAndroid && _audioPassthroughEnabled})' → 'MUT(passthrough=${!kIsWeb && Platform.isAndroid && _audioPassthroughEnabled})'` | killed; `sweep/p017` |
| `p018` | `_installSubtitleAutoSyncForPlayer`:1969 | `&& → \|\|` | device-pending; `closure/p018` |
| `p019` | `_installSubtitleAutoSyncForPlayer`:1969 | `&& → \|\|` | killed; `sweep/p019` |
| `p020` | `_installSubtitleAutoSyncForPlayer`:1971 | `_subtitleAutoSync = MediaKitSubtitleAutoSync(       player: platform,       enabled: _subtitleAutoSyncEnabled,       pas… → <removed>` | killed; `sweep/p020` |
| `p021` | `_installSubtitleAutoSyncForPlayer`:1975 | `&& → \|\|` | device-pending; `closure/p021` |
| `p022` | `_installSubtitleAutoSyncForPlayer`:1975 | `&& → \|\|` | killed; `sweep/p022` |
| `p023` | `_installSubtitleAutoSyncForPlayer`:1978 | `0 → 1` | killed; `sweep/p023` |
| `p024` | `_disposeSubtitleAutoSync`:1985 | `final controller = _subtitleAutoSync; → final controller = null as MediaKitSubtitleAutoSync?;` | killed; `sweep/p024` |
| `p025` | `_disposeSubtitleAutoSync`:1986 | `_subtitleAutoSync = null; → <removed>` | killed; `closure/p025` |
| `p027` | `_disposeSubtitleAutoSync`:1987 | `_hideAutoSyncPill(); → <removed>` | killed; `sweep/p027` |
| `p028` | `_disposeSubtitleAutoSync`:1988 | `await controller?.dispose(); → <removed>` | killed; `sweep/p028` |
| `p029` | `_applyAutoSubtitleSyncOffset`:1992 | `final clamped = milliseconds.clamp(       SubtitleSettingsService.syncOffsetMinMs,       SubtitleSettingsService.syncOff… → final clamped = 0;` | killed; `sweep/p029` |
| `p030` | `_applyAutoSubtitleSyncOffset`:1996 | `!mounted → (!mounted) \|\| true` | killed; `sweep/p030` |
| `p031` | `_applyAutoSubtitleSyncOffset`:1996 | `return; → <removed>` | killed; `sweep/p031` |
| `p032` | `_applyAutoSubtitleSyncOffset`:1997 | `_subtitleSettings = _subtitleSettings?.copyWith(syncOffsetMs: clamped); → <removed>` | killed; `sweep/p032` |
| `p033` | `_applyAutoSubtitleSyncOffset`:1998 | `_applySubtitleSyncOffset(clamped); → <removed>` | killed; `sweep/p033` |
| `p034` | `_applyAutoSubtitleSyncOffset`:1999 | `setState(() {}); → <removed>` | killed; `closure/p034` |
| `p035` | `_applyAutoSubtitleSyncOffset`:2001 | `await SubtitleSettingsService.instance.setSyncOffsetMs(clamped); → <removed>` | killed; `sweep/p035` |
| `p036` | `_applyAutoSubtitleSyncOffset`:2005 | `debugPrint('SubtitleAutoSync: offset persistence failed: $error'); → <removed>` | dormant; `closure/p036` |
| `p037` | `_applyAutoSubtitleSyncOffset`:2005 | `'SubtitleAutoSync: offset persistence failed: $error' → 'MUTSubtitleAutoSync: offset persistence failed: $error'` | dormant; `closure/p037` |
| `p038` | `_showSubtitleAutoSyncNotice`:2010 | `!mounted → (!mounted) \|\| true` | killed; `witness/p038` |
| `p039` | `_showSubtitleAutoSyncNotice`:2010 | `return; → <removed>` | killed; `sweep/p039` |
| `p040` | `_showSubtitleAutoSyncNotice`:2012 | `debugPrint('SubtitleAutoSync: ${notice.message}'); → <removed>` | killed; `sweep/p040` |
| `p041` | `_showSubtitleAutoSyncNotice`:2012 | `'SubtitleAutoSync: ${notice.message}' → 'MUTSubtitleAutoSync: ${notice.message}'` | killed; `closure/p041` |
| `p043` | `_showSubtitleAutoSyncNotice`:2016 | `_openAutoSyncPillWindow(); → <removed>` | killed; `sweep/p043` |
| `p045` | `_showSubtitleAutoSyncNotice`:2020 | `_autoSyncWindowActive → false && (_autoSyncWindowActive)` | killed; `sweep/p045` |
| `p046` | `_showSubtitleAutoSyncNotice`:2021 | `_autoSyncPillPhaseTimer?.cancel(); → <removed>` | equivalent; `final-closure/p046` |
| `p047` | `_showSubtitleAutoSyncNotice`:2022 | `_autoSyncPill.value = const AutoSyncPillModel(             AutoSyncPillPhase.checking,           ); → <removed>` | killed; `sweep/p047` |
| `p049` | `_showSubtitleAutoSyncNotice`:2028 | `_autoSyncWindowActive &&             _autoSyncPill.value?.phase == AutoSyncPillPhase.checking → false && (_autoSyncWindowActive &&             _autoSyncPill.value?.phase == AutoSyncPillPhase.checking)` | killed; `sweep/p049` |
| `p050` | `_showSubtitleAutoSyncNotice`:2028 | `&& → \|\|` | equivalent; `final-closure/p050` |
| `p051` | `_showSubtitleAutoSyncNotice`:2029 | `== → !=` | killed; `sweep/p051` |
| `p052` | `_showSubtitleAutoSyncNotice`:2030 | `_autoSyncPill.value = null; → <removed>` | killed; `sweep/p052` |
| `p055` | `_showSubtitleAutoSyncNotice`:2035 | `notice.kind == SubtitleAutoSyncNoticeKind.resynced &&             !_autoSyncWindowActive &&             _autoSyncPill.va… → false && (notice.kind == SubtitleAutoSyncNoticeKind.resynced &&             !_autoSyncWindowActive &&             _autoS…` | killed; `sweep/p055` |
| `p056` | `_showSubtitleAutoSyncNotice`:2035 | `&& → \|\|` | killed; `closure/p056` |
| `p057` | `_showSubtitleAutoSyncNotice`:2035 | `&& → \|\|` | killed; `closure/p057` |
| `p058` | `_showSubtitleAutoSyncNotice`:2035 | `== → !=` | killed; `sweep/p058` |
| `p059` | `_showSubtitleAutoSyncNotice`:2037 | `== → !=` | killed; `sweep/p059` |
| `p061` | `_showSubtitleAutoSyncNotice`:2038 | `return; → <removed>` | killed; `sweep/p061` |
| `p062` | `_showSubtitleAutoSyncNotice`:2040 | `_showAutoSyncPillResult(AutoSyncPillPhase.synced); → <removed>` | killed; `sweep/p062` |
| `p064` | `_showSubtitleAutoSyncNotice`:2042 | `_showAutoSyncPillResult(AutoSyncPillPhase.failed); → <removed>` | killed; `sweep/p064` |
| `p065` | `_openAutoSyncPillWindow`:2047 | `_autoSyncPillHold?.cancel(); → <removed>` | killed; `closure/p065` |
| `p066` | `_openAutoSyncPillWindow`:2048 | `_autoSyncPillHold = null; → <removed>` | equivalent; `final-closure/p066` |
| `p068` | `_openAutoSyncPillWindow`:2049 | `_autoSyncWindowActive = true; → <removed>` | killed; `sweep/p068` |
| `p069` | `_openAutoSyncPillWindow`:2049 | `true → false` | killed; `sweep/p069` |
| `p070` | `_openAutoSyncPillWindow`:2050 | `_autoSyncPill.value = const AutoSyncPillModel(AutoSyncPillPhase.announce); → <removed>` | killed; `sweep/p070` |
| `p071` | `_openAutoSyncPillWindow`:2051 | `_autoSyncPillPhaseTimer?.cancel(); → <removed>` | killed; `closure/p071` |
| `p072` | `_openAutoSyncPillWindow`:2052 | `_autoSyncPillPhaseTimer = Timer(const Duration(seconds: 5), () {       // The sentence had its moment; the screen goes q… → <removed>` | killed; `closure/p072` |
| `p073` | `_openAutoSyncPillWindow`:2052 | `5 → 6` | killed; `closure/p073` |
| `p074` | `_openAutoSyncPillWindow`:2055 | `_autoSyncWindowActive &&           _autoSyncPill.value?.phase == AutoSyncPillPhase.announce → false && (_autoSyncWindowActive &&           _autoSyncPill.value?.phase == AutoSyncPillPhase.announce)` | killed; `sweep/p074` |
| `p075` | `_openAutoSyncPillWindow`:2055 | `&& → \|\|` | equivalent; `final-closure/p075` |
| `p076` | `_openAutoSyncPillWindow`:2056 | `== → !=` | killed; `sweep/p076` |
| `p077` | `_openAutoSyncPillWindow`:2057 | `_autoSyncPill.value = null; → <removed>` | killed; `sweep/p077` |
| `p079` | `_showAutoSyncPillResult`:2063 | `_autoSyncWindowActive = false; → <removed>` | equivalent; `final-closure/p079` |
| `p080` | `_showAutoSyncPillResult`:2063 | `false → true` | equivalent; `final-closure/p080` |
| `p081` | `_showAutoSyncPillResult`:2064 | `_autoSyncPillPhaseTimer?.cancel(); → <removed>` | equivalent; `final-closure/p081` |
| `p082` | `_showAutoSyncPillResult`:2065 | `_autoSyncPillPhaseTimer = null; → <removed>` | equivalent; `final-closure/p082` |
| `p084` | `_showAutoSyncPillResult`:2066 | `_autoSyncPillHold?.cancel(); → <removed>` | equivalent; `final-closure/p084` |
| `p085` | `_showAutoSyncPillResult`:2067 | `_autoSyncPill.value = AutoSyncPillModel(phase); → <removed>` | killed; `sweep/p085` |
| `p086` | `_showAutoSyncPillResult`:2068 | `_autoSyncPillHold = Timer(       const Duration(milliseconds: 2400),       _hideAutoSyncPill,     ); → <removed>` | killed; `closure/p086` |
| `p087` | `_showAutoSyncPillResult`:2069 | `2400 → 2401` | killed; `closure/p087` |
| `p088` | `_hideAutoSyncPill`:2075 | `_autoSyncWindowActive = false; → <removed>` | killed; `final-closure/p088` |
| `p089` | `_hideAutoSyncPill`:2075 | `false → true` | killed; `sweep/p089` |
| `p090` | `_hideAutoSyncPill`:2076 | `_autoSyncPillPhaseTimer?.cancel(); → <removed>` | killed; `closure/p090` |
| `p091` | `_hideAutoSyncPill`:2077 | `_autoSyncPillPhaseTimer = null; → <removed>` | equivalent; `final-closure/p091` |
| `p093` | `_hideAutoSyncPill`:2078 | `_autoSyncPillHold?.cancel(); → <removed>` | killed; `closure/p093` |
| `p094` | `_hideAutoSyncPill`:2079 | `_autoSyncPillHold = null; → <removed>` | equivalent; `final-closure/p094` |
| `p096` | `_hideAutoSyncPill`:2080 | `_autoSyncPill.value != null → false && (_autoSyncPill.value != null)` | killed; `sweep/p096` |
| `p097` | `_hideAutoSyncPill`:2080 | `!= → ==` | killed; `sweep/p097` |
| `p099` | `_hideAutoSyncPill`:2080 | `_autoSyncPill.value = null; → {}` | killed; `closure/p099-block` |
| `p101` | `_setActiveExternalSubtitlePath`:2084 | `_activeExternalSubtitlePath == path → (_activeExternalSubtitlePath == path) \|\| true` | killed; `witness/p101` |
| `p102` | `_setActiveExternalSubtitlePath`:2084 | `== → !=` | killed; `sweep/p102` |
| `p103` | `_setActiveExternalSubtitlePath`:2084 | `return; → <removed>` | killed; `sweep/p103` |
| `p104` | `_setActiveExternalSubtitlePath`:2085 | `_activeExternalSubtitlePath = path; → <removed>` | killed; `sweep/p104` |
| `p105` | `_setActiveExternalSubtitlePath`:2086 | `final controller = _subtitleAutoSync; → final controller = null as MediaKitSubtitleAutoSync?;` | killed; `sweep/p105` |
| `p106` | `_setActiveExternalSubtitlePath`:2087 | `debugPrint(       'SubtitleAutoSync: external subtitle ${path == null ? 'cleared' : 'set'} '       '(controller=${contro… → <removed>` | killed; `sweep/p106` |
| `p107` | `_setActiveExternalSubtitlePath`:2088 | `'SubtitleAutoSync: external subtitle ${path == null ? 'cleared' : 'set'} ' → 'MUTSubtitleAutoSync: external subtitle ${path == null ? 'cleared' : 'set'} '` | killed; `sweep/p107` |
| `p108` | `_setActiveExternalSubtitlePath`:2088 | `path == null → !(path == null)` | killed; `sweep/p108` |
| `p109` | `_setActiveExternalSubtitlePath`:2088 | `== → !=` | killed; `sweep/p109` |
| `p111` | `_setActiveExternalSubtitlePath`:2088 | `'cleared' → "cleared mutant"` | killed; `closure/p111` |
| `p112` | `_setActiveExternalSubtitlePath`:2088 | `'set' → "set mutant"` | killed; `sweep/p112` |
| `p113` | `_setActiveExternalSubtitlePath`:2089 | `'(controller=${controller == null ? 'MISSING' : 'present'})' → 'MUT(controller=${controller == null ? 'MISSING' : 'present'})'` | killed; `sweep/p113` |
| `p114` | `_setActiveExternalSubtitlePath`:2089 | `controller == null → !(controller == null)` | killed; `sweep/p114` |
| `p115` | `_setActiveExternalSubtitlePath`:2089 | `== → !=` | killed; `sweep/p115` |
| `p117` | `_setActiveExternalSubtitlePath`:2089 | `'MISSING' → "MISSING mutant"` | killed; `sweep/p117` |
| `p118` | `_setActiveExternalSubtitlePath`:2089 | `'present' → "present mutant"` | killed; `sweep/p118` |
| `p119` | `_setActiveExternalSubtitlePath`:2091 | `controller == null → controller == null \|\| _subtitleAutoSyncEnabled` | killed; `final-closure/p119-valid` |
| `p120` | `_setActiveExternalSubtitlePath`:2091 | `== → !=` | invalid-candidate; `sweep/p120` |
| `p122` | `_setActiveExternalSubtitlePath`:2091 | `return; → return _openAutoSyncPillWindow();` | killed; `extra/p122-exit-effect` |
| `p123` | `_setActiveExternalSubtitlePath`:2092 | `path == null → path == null \|\| _subtitleAutoSyncEnabled` | killed; `final-closure/p123-valid` |
| `p124` | `_setActiveExternalSubtitlePath`:2092 | `== → !=` | invalid-candidate; `sweep/p124` |
| `p126` | `_setActiveExternalSubtitlePath`:2093 | `unawaited(controller.deactivateSubtitle()); → <removed>` | killed; `sweep/p126` |
| `p127` | `_setActiveExternalSubtitlePath`:2094 | `_hideAutoSyncPill(); → <removed>` | killed; `closure/p127` |
| `p128` | `_setActiveExternalSubtitlePath`:2096 | `unawaited(controller.activateSubtitle(path)); → <removed>` | killed; `sweep/p128` |
| `p129` | `_loadSubtitleSettings`:5405 | `final settings = await SubtitleSettingsService.instance.loadAll(); → final settings = (await SubtitleSettingsService.instance.loadAll()).copyWith(colorIndex: 0, syncOffsetMs: 0);` | killed; `witness/p129` |
| `p130` | `_loadSubtitleSettings`:5406 | `mounted → false && (mounted)` | killed; `sweep/p130` |
| `p131` | `_loadSubtitleSettings`:5407 | `setState(() {         _subtitleSettings = settings;       }); → <removed>` | killed; `sweep/p131` |
| `p132` | `_loadSubtitleSettings`:5408 | `_subtitleSettings = settings; → <removed>` | killed; `sweep/p132` |
| `p133` | `_loadSubtitleSettings`:5410 | `settings.syncOffsetMs != 0 → false && (settings.syncOffsetMs != 0)` | killed; `closure/p133` |
| `p134` | `_loadSubtitleSettings`:5410 | `!= → ==` | killed; `sweep/p134` |
| `p135` | `_loadSubtitleSettings`:5410 | `0 → 1` | killed; `sweep/p135` |
| `p136` | `_loadSubtitleSettings`:5411 | `_applySubtitleSyncOffset(settings.syncOffsetMs); → <removed>` | killed; `closure/p136` |
| `p137` | `_onSubtitleStyleChanged`:5553 | `!mounted → false && !mounted` | killed; `witness/p137-unguarded` |
| `p138` | `_onSubtitleStyleChanged`:5553 | `return; → {}` | killed; `final-closure/p138-valid` |
| `p139` | `_onSubtitleStyleChanged`:5554 | `final offsetChanged =         _subtitleSettings?.syncOffsetMs != settings.syncOffsetMs; → final offsetChanged = false;` | killed; `sweep/p139` |
| `p140` | `_onSubtitleStyleChanged`:5555 | `!= → ==` | killed; `sweep/p140` |
| `p141` | `_onSubtitleStyleChanged`:5556 | `setState(() {       _subtitleSettings = settings;     }); → <removed>` | killed; `sweep/p141` |
| `p142` | `_onSubtitleStyleChanged`:5557 | `_subtitleSettings = settings; → <removed>` | killed; `sweep/p142` |
| `p143` | `_onSubtitleStyleChanged`:5559 | `offsetChanged → false && (offsetChanged)` | killed; `sweep/p143` |
| `p144` | `_onSubtitleStyleChanged`:5560 | `_subtitleAutoSync?.manualOffsetChanged(settings.syncOffsetMs); → <removed>` | killed; `closure/p144` |
| `p145` | `_onSubtitleStyleChanged`:5561 | `_hideAutoSyncPill(); → <removed>` | killed; `sweep/p145` |
| `p146` | `_onSubtitleStyleChanged`:5562 | `_applySubtitleSyncOffset(settings.syncOffsetMs); → <removed>` | killed; `sweep/p146` |
| `p147` | `_applySubtitleSyncOffset`:5567 | `final platform = _player.platform; → final platform = null as mk.PlatformPlayer?;` | killed; `witness/p147` |
| `p148` | `_applySubtitleSyncOffset`:5568 | `platform is mk.NativePlayer → false && (platform is mk.NativePlayer)` | killed; `sweep/p148` |
| `p149` | `_applySubtitleSyncOffset`:5569 | `platform.setProperty('sub-delay', (ms / 1000.0).toStringAsFixed(3)); → <removed>` | killed; `sweep/p149` |
| `p150` | `_applySubtitleSyncOffset`:5569 | `'sub-delay' → "sub-delay mutant"` | killed; `sweep/p150` |
| `p151` | `_applySubtitleSyncOffset`:5569 | `/ → *` | killed; `sweep/p151` |
| `p152` | `_applySubtitleSyncOffset`:5569 | `1000.0 → 2000.0` | killed; `sweep/p152` |
| `p153` | `_applySubtitleSyncOffset`:5569 | `3 → 4` | killed; `sweep/p153` |
| `p154` | `_resetSubtitleSyncOffset`:5578 | `SubtitleSettingsService.instance.resetSyncOffset(); → <removed>` | killed; `witness/p154` |
| `p155` | `_resetSubtitleSyncOffset`:5581 | `_subtitleSettings = _subtitleSettings?.copyWith(syncOffsetMs: 0); → <removed>` | killed; `sweep/p155` |
| `p156` | `_resetSubtitleSyncOffset`:5581 | `0 → 1` | killed; `sweep/p156` |
| `p157` | `_resetSubtitleSyncOffset`:5582 | `_applySubtitleSyncOffset(0); → <removed>` | killed; `sweep/p157` |
| `p158` | `_resetSubtitleSyncOffset`:5582 | `0 → 1` | killed; `sweep/p158` |
| `p159` | `_showSyncOverlayPanel`:5595 | `_tvReleaseFocusForOverlay(); → <removed>` | killed; `sweep/p159` |
| `p160` | `_showSyncOverlayPanel`:5596 | `setState(() {       _showSyncOverlay = true;       _controlsVisible.value = false;     }); → <removed>` | killed; `witness/p160` |
| `p161` | `_showSyncOverlayPanel`:5597 | `_showSyncOverlay = true; → <removed>` | killed; `sweep/p161` |
| `p162` | `_showSyncOverlayPanel`:5597 | `true → false` | killed; `sweep/p162` |
| `p163` | `_showSyncOverlayPanel`:5598 | `_controlsVisible.value = false; → <removed>` | killed; `final-closure/p163` |
| `p164` | `_showSyncOverlayPanel`:5598 | `false → true` | killed; `closure/p164` |
| `p165` | `_hideSyncOverlay`:5603 | `setState(() => _showSyncOverlay = false); → <removed>` | killed; `closure/p165` |
| `p166` | `_hideSyncOverlay`:5603 | `false → true` | killed; `closure/p166` |
| `p167` | `_buildSyncOverlay`:5607 | `final externalPath = _activeExternalSubtitlePath; → final externalPath = null as String?;` | killed; `sweep/p167` |
| `p168` | `_buildSyncOverlay`:5608 | `externalPath != null → externalPath != null && !_subtitleAutoSyncEnabled` | killed; `final-closure/p168-valid` |
| `p169` | `_buildSyncOverlay`:5608 | `!= → ==` | invalid-candidate; `sweep/p169` |
| `p171` | `_buildSyncOverlay`:5609 | `return SubtitleLinePickerOverlay(         subtitleFilePath: externalPath,         getCurrentPositionMs: () => _player.st… → return const SizedBox.shrink();` | killed; `sweep/p171` |
| `p172` | `_buildSyncOverlay`:5612 | `0 → 1` | killed; `closure/p172` |
| `p173` | `_buildSyncOverlay`:5614 | `await SubtitleSettingsService.instance.setSyncOffsetMs(ms); → <removed>` | killed; `sweep/p173` |
| `p174` | `_buildSyncOverlay`:5615 | `_subtitleAutoSync?.manualOffsetChanged(ms); → <removed>` | killed; `closure/p174` |
| `p175` | `_buildSyncOverlay`:5616 | `_hideAutoSyncPill(); → <removed>` | killed; `sweep/p175` |
| `p176` | `_buildSyncOverlay`:5617 | `_applySubtitleSyncOffset(ms); → <removed>` | killed; `sweep/p176` |
| `p177` | `_buildSyncOverlay`:5618 | `mounted → false && (mounted)` | killed; `sweep/p177` |
| `p178` | `_buildSyncOverlay`:5619 | `setState(() {               _subtitleSettings = _subtitleSettings?.copyWith(syncOffsetMs: ms);             }); → <removed>` | killed; `sweep/p178` |
| `p179` | `_buildSyncOverlay`:5620 | `_subtitleSettings = _subtitleSettings?.copyWith(syncOffsetMs: ms); → <removed>` | killed; `sweep/p179` |
| `p180` | `_buildSyncOverlay`:5628 | `return _buildSliderSyncOverlay(); → return const SizedBox.shrink();` | killed; `sweep/p180` |
| `p181` | `_buildSliderSyncOverlay`:5632 | `return SyncStepperOverlay(       offsetMs: _subtitleSettings?.syncOffsetMs ?? 0,       onOffsetChanged: (ms) async {    … → return const SizedBox.shrink();` | killed; `sweep/p181` |
| `p182` | `_buildSliderSyncOverlay`:5633 | `0 → 1` | killed; `closure/p182` |
| `p183` | `_buildSliderSyncOverlay`:5635 | `final clamped = ms.clamp(           SubtitleSettingsService.syncOffsetMinMs,           SubtitleSettingsService.syncOffse… → final clamped = 0;` | killed; `sweep/p183` |
| `p184` | `_buildSliderSyncOverlay`:5639 | `await SubtitleSettingsService.instance.setSyncOffsetMs(clamped); → <removed>` | killed; `sweep/p184` |
| `p185` | `_buildSliderSyncOverlay`:5640 | `_subtitleAutoSync?.manualOffsetChanged(clamped); → <removed>` | killed; `closure/p185` |
| `p186` | `_buildSliderSyncOverlay`:5641 | `_hideAutoSyncPill(); → <removed>` | killed; `closure/p186` |
| `p187` | `_buildSliderSyncOverlay`:5642 | `_applySubtitleSyncOffset(clamped); → <removed>` | killed; `sweep/p187` |
| `p188` | `_buildSliderSyncOverlay`:5643 | `mounted → false && (mounted)` | killed; `sweep/p188` |
| `p189` | `_buildSliderSyncOverlay`:5644 | `setState(() {             _subtitleSettings = _subtitleSettings?.copyWith(               syncOffsetMs: clamped,         … → <removed>` | killed; `sweep/p189` |
| `p190` | `_buildSliderSyncOverlay`:5645 | `_subtitleSettings = _subtitleSettings?.copyWith(               syncOffsetMs: clamped,             ); → <removed>` | killed; `sweep/p190` |

### Equivalence and coverage limits

| Candidate | Classification / original caller proof |
|---|---|
| `p001` | equivalent: Defaults are awaited before create/bind/install; the initializer has no read before that assignment. A defaults failure aborts construction. The 33-reference AST ledger exhausts readers. |
| `p018` | device-pending: the mutation replaces the final `&&` with `||`; on native Android with passthrough **off** it turns `false` into `true` (with passthrough on both return `true`). The desktop storage preference is not loaded into this field; raw Android menu/loader guards are outside S2, so the passthrough-off Android case is device-pending. (Corrected after vp-rev9 P3.) |
| `p021` | device-pending: same `&&`→`||` change in the engine constructor's passthrough argument — differs on native Android with passthrough **off** (`false`→`true`); raw Android guards are outside S2, so device-pending. Inner conjunction mutation is separately killed; no positive passthrough coverage claimed. (Corrected after vp-rev9 P3.) |
| `p036` | dormant: setSyncOffsetMs only clamps/stores session int and has no throwing persistence transport; native property rejection occurs before this try. No preference failure can reach this diagnostic via original callers. |
| `p037` | dormant: Same unreachable session-only persistence catch as p036. Diagnostic preserved verbatim. |
| `p046` | equivalent: No facade runNow caller. Announcement expires at 5s; first checking is >=8s. A restart cancels the old announce and starts a fresh 8s ladder. No active phase timer remains at checking. |
| `p050` | equivalent: A stillListening notice follows checking within the same run/generation; active window then has checking model. Quiet cold window has neither. Manual/path/audio retirement invalidates that run; no mixed-operand state reaches the notice. |
| `p066` | equivalent: After cancel, this private Timer reference is only canceled again or overwritten; no identity/activity consumer. No callback survives cancel. |
| `p075` | equivalent: At announce deadline, an active phase timer belongs to the latest listening window. Any terminal/manual/path hide cancels it. No active timer observes one false operand and one true operand. |
| `p079` | equivalent: A verdict cancels the 8s ladder. Its 2400ms hold clears the flag before any new >=8s ladder checking; fresh listening overwrites true, and verification >=90s follows hide. No other window reader during result hold. |
| `p080` | equivalent: Same result-hold/ladder/verification ordering as p079. |
| `p081` | equivalent: No active 5s announce timer at the first >=8s verdict; checking already canceled it. Verification never creates a phase timer. |
| `p082` | equivalent: Canceled/expired phase reference is never tested/read for identity; next scheduling replaces it. |
| `p084` | equivalent: The old result hold ends after2400ms, before any subsequent >=8s verdict or >=90s verification. Fresh listening cancels the hold. No two live verdict-hold callbacks can overlap through original engine callers. |
| `p091` | equivalent: After cancel, the phase Timer reference is only canceled again or overwritten; no identity consumer. |
| `p094` | equivalent: After cancel, hold Timer reference is only canceled again or overwritten; no identity consumer. |
| `p120` | invalid-candidate: flow/type/syntax violation; no kill credit. Parent branch/snapshot/body behaviour has separate valid mutations. |
| `p124` | invalid-candidate: flow/type/syntax violation; no kill credit. Parent branch/snapshot/body behaviour has separate valid mutations. |
| `p169` | invalid-candidate: flow/type/syntax violation; no kill credit. Parent branch/snapshot/body behaviour has separate valid mutations. |

### Final per-test mutation witnesses

| New behaviour test (unchanged final input) | Original assertion-failing witness |
|---|---|
| real subtitle engine announces then aligns fixture metadata | `retained/r04` |
| subtitle TV Android TV first key repeat and Back retain overlay element | `retained/r18` |
| subtitle TV line picker receives the first Select through the focus release | `retained/r29` |
| subtitle TV tvOS first key repeat and Back retain overlay element | `retained/r29` |
| subtitle already returned snapshot after disposal is rejected | `retained/r01` |
| subtitle already returned snapshot after profile handoff is accepted by mounted only | `retained/r01` |
| subtitle audio track event restarts announcement and manual offset cancels the ladder | `retained/r06` |
| subtitle auto verdict rebuilds an already open sync overlay with the computed offset | `retained/r04` |
| subtitle automatic source priority activates the real engine through its retained caller | `retained/r33` |
| subtitle automatic source priority retires on preferred audio | `retained/r32` |
| subtitle checking stays visible until real alignment finishes | `retained/r04` |
| subtitle cold window remains quiet when a late session offset suppresses listening then a track reset releases the ladder | `retained/r11` |
| subtitle content replacement clears timing and path but a saved line callback targets the new playback | `retained/r30` |
| subtitle desktop passthrough preference still uses the raw Android predicate | `retained/r11` |
| subtitle dispose cancels announcement before notifier disposal | `retained/r11` |
| subtitle dispose cancels result hold before notifier disposal | `retained/r11` |
| subtitle early stepper reads zero while the original settings snapshot is suspended | `retained/r19` |
| subtitle enabled nonnative backend records rejection and stores the external path without an engine | `retained/r11` |
| subtitle engine offset before settings delivery keeps null UI model and accepts the old snapshot later | `retained/r11` |
| subtitle exhausted unrelated metadata produces a failed result | `retained/r04` |
| subtitle file filter installation held across disposal is removed before player teardown | `retained/r15` |
| subtitle file filter installation held across subtitle change is removed before player teardown | `witness/p101` |
| subtitle fresh audio listening cancels a failed verdict hold | `retained/r04` |
| subtitle fresh listening cancels the preceding announcement deadline | `retained/r04` |
| subtitle held alignment handles the retained new audio subscription | `retained/r06` |
| subtitle held alignment handles the retained same audio subscription | `witness/p147` |
| subtitle held alignment handles the retained seek jump subscription | `retained/r05` |
| subtitle held alignment handles the retained small position subscription | `witness/p147` |
| subtitle intermediate no verdict quietly keeps listening | `retained/r04` |
| subtitle late decoder rollback restores the previous external path and reactivates the real engine | `retained/r10` |
| subtitle line picker updates session and native delay and dismisses | `retained/r29` |
| subtitle manual hide keeps a later offset-suppressed selection quiet when its ladder is rearmed | `retained/r11` |
| subtitle native auto property rejection escapes the persistence catch and still reports synced | `retained/r11` |
| subtitle native manual property rejection escapes while session and UI still update | `witness/p147` |
| subtitle off then new selection cannot inherit an old announcement hide | `retained/r04` |
| subtitle off then new selection cannot inherit an old result hide | `retained/r04` |
| subtitle overlapping route resets singleton offset while the outgoing route retains its model | `retained/r01` |
| subtitle pending filter removal across disposal preserves the lifecycle queue | `retained/r15` |
| subtitle pending filter removal across subtitle change preserves the lifecycle queue | `witness/p101` |
| subtitle pending font lookup after shared prefs reset propagates null prefs error | `retained/r01` |
| subtitle pending font lookup after shared prefs reset reads incoming prefs and font | `retained/r01` |
| subtitle real alignment held across disposal cannot apply the retired result | `witness/p101` |
| subtitle real alignment held across renderer replacement cannot apply the retired result | `retained/r08` |
| subtitle real alignment held across subtitle change cannot apply the retired result | `witness/p101` |
| subtitle renderer replacement awaits engine filter removal before old player disposal | `retained/r08` |
| subtitle replacement clears the disposed engine before incoming audio setup and a saved selection | `retained/r08` |
| subtitle rollback held through disposal sees the cleared engine before the mounted UI guard | `retained/r11` |
| subtitle route Back dismisses the top sync overlay before leaving playback | `retained/r17` |
| subtitle saved line manual callback cancels a held real alignment and hides checking | `witness/p147` |
| subtitle saved line picker callback after dismissal keeps original effect order | `witness/p147` |
| subtitle saved line picker callback after disposal keeps original effect order | `witness/p101` |
| subtitle saved line picker callback after replacement keeps original effect order | `witness/p147` |
| subtitle saved stepper callback after dismissal keeps original effect order | `witness/p147` |
| subtitle saved stepper callback after disposal keeps original effect order | `witness/p147` |
| subtitle saved stepper callback after replacement keeps original effect order | `witness/p147` |
| subtitle saved stepper manual callback cancels a held real alignment and hides checking | `witness/p147` |
| subtitle selected before engine installation remains inactive even when the same path is selected again | `witness/p101` |
| subtitle stepper clamps callback -4000000 before native and rendered writes | `witness/p147` |
| subtitle stepper clamps callback 4000000 before native and rendered writes | `witness/p147` |
| subtitle stepper updates session and native delay and dismisses | `retained/r29` |
| subtitle stored enablement false gates actual installation and selection | `retained/r12` |
| subtitle stored enablement true gates actual installation and selection | `retained/r11` |
| subtitle style callback renders appearance without restarting unchanged timing | `retained/r28` |
| subtitle style callback saved before disposal skips all later effects | `witness/p137-unguarded` |
| subtitle style timing feedback invalidates a held real alignment before its offset can win | `retained/r04` |
| subtitle suspended prefs initialization can overwrite incoming cache with a stale profile wrapper | `extra/e-load-error` |
| subtitle timing is session only while appearance migrates and persists | `witness/p147` |
| subtitle timing reset clears session and native property | `retained/r27` |
| subtitle timing reset clears session and skips nonnative property | `retained/r27` |
| subtitle verification corrects later drift silently after the result pill fades | `retained/r04` |


Each evidence path above is relative to `p9/step0/`; full patches and assertion
messages are archived there. Production creation, CI/theme/source-guard
registration, source-test retargets, size reduction, release builds and M2 remain
unstarted. Step 1 registers these six test files in `ci_behavior_tests.txt` and
moves the current manifest/analyzer inputs to P9; Step 0 leaves applied P8 active.


### Step-0 additions-only suite baseline

Fresh complete `suite_evidence.py run vplayer/p9/step0/baseline --no-pub
--dart-define=DEBRIFY_VP_TEST_HOOKS=true` (nice19) completes in 923 seconds.
Comparison with M1's recorded baseline **PASS**: **13,463 success / 13 failure /
28 load error / 20 skip**, exactly **70 passing additions** and no changed,
missing, newly skipped or fixed old identity. Same Flutter3.44.8/Dart3.12.2;
tracked tested tree stable during the run. `baseline-additions.json` records
all identities. No baseline/allowlist recording used to accept a regression.
Final new-file analysis and formatting, size and architecture checks PASS;
Step T's 38 mechanical jobs and S/S2/S2b proofs remain valid with unchanged
application/tool inputs. No new test flake required a stabilization.


## Phase 9 Step 0b — independent sample closure

Claude independent sample on original `122896451`: **16/20 reported kills (80%)**. The
addendum adds two original-caller behaviours without production changes. The
aligner bounds each pass (90s wide /10s residual), but the engine sums residuals;
it does **not** bound cumulative offsets. The fixture supplies isolated speech
windows through real SRT/parser/metadata/compute and advances the real playback
clock, then pins 41 successive corrections and the final native/session/overlay
clamp. Sparse windows keep the two narrow misses deterministic before each wide
verdict; no result/notice is forged. The negative load case uses the existing
font barrier and an outgoing saved stepper callback after incoming startup reset.

The two notice predicates are equivalent for the original's production caller
graph: `stillListening` follows the same generation's Checking, whereas resync
starts at 90s, after the 2400ms result hide. Fresh activation/audio events retire
old generations; holding compute cannot create a mixed-generation notice. All
window writers and engine notice/teardown paths were audited. Full source copies,
hashes and detailed invariants are in `p9/step0b/adjudications.json`; m7/m8
replay all 72 cases with complete successful controls. This is not a synthetic
notice test or a device-pending classification.

| Sample | Final classification | Witness / reason |
|---|---|---|
| `m1` | killed in independent sample | subtitle stored enablement false gates actual installation and selection |
| `m2` | killed in independent sample | subtitle manual hide keeps a later offset-suppressed selection quiet when its ladder is rearmed; subtitle cold window remains quiet when a late session offset suppresses listening then a track reset releases the ladder; subtitle verification corrects later drift silently after the result pill fades |
| `m3` | killed in independent sample | subtitle renderer replacement awaits engine filter removal before old player disposal |
| `m4` | killed in addendum | Non-equivalent. Per-pass searchMs=90000 is not a total bound: verification centers cues at the previous applied offset and calls applyOffsetMs(applied + result.offsetMs). The real-caller test feeds 41 disjoint speech/metadata windows with +89s successive drift; two narrow NoMatch results precede each wide actual Synced result. The last verdict exceeds +3600000; native, overlay model and session retain the clamp. No forged result or notice. |
| `m5` | killed in independent sample | subtitle auto verdict rebuilds an already open sync overlay with the computed offset; subtitle verification corrects later drift silently after the result pill fades |
| `m6` | killed in independent sample | subtitle manual hide keeps a later offset-suppressed selection quiet when its ladder is rearmed; subtitle cold window remains quiet when a late session offset suppresses listening then a track reset releases the ladder |
| `m7` | equivalent; original-caller audit + 72-case replay | Equivalent under original callers. Every stillListening call is synchronous after this same run emitted checking, passed disposed/generation/run/path/reliability guards, and returned NoMatch/NotEnoughAudio. In an active window checking cancels the announcement timer and installs Checking. A fresh listening event requires activation/audio restart, both increment generation/run before emitting listening; that makes the old result stale. A hold/result cannot be created by another run while this run owns _running; the ladder tests _running before tap failure. Manual/path/disposal hide paths clear the window or retire the run. Thus the only active-window value at stillListening is Checking; quiet windows cause no write in either version, and null-to-null assignments notify nobody. |
| `m8` | equivalent; original-caller audit + 72-case replay | Equivalent under original callers. After synced, showAutoSyncPillResult sets window false and arms the 2400ms hide; only afterward does the engine arm its first verification for 90s, then 120s. No same-generation ladder remains armed after success. Holding the verification result only extends this gap; it cannot keep the expired result pill visible. Fresh listening/result from subtitle/audio/passthrough/replacement operations retires the old generation/controller before it can emit resynced. Manual hide clears the pill. For a surviving resynced event in an inactive window, the pill is null; both guards return. Counterexamples would require forging a notice or suppressing an already due earlier timer independently of the original scheduler. |
| `m9` | killed in independent sample | subtitle fresh audio listening cancels a failed verdict hold; subtitle exhausted unrelated metadata produces a failed result |
| `m10` | killed in independent sample | subtitle off then new selection cannot inherit an old announcement hide; subtitle fresh listening cancels the preceding announcement deadline; real subtitle engine announces then aligns fixture metadata; subtitle audio track event restarts announcement and manual offset cancels the ladder |
| `m11` | killed in independent sample | subtitle off then new selection cannot inherit an old result hide; subtitle fresh audio listening cancels a failed verdict hold; subtitle verification corrects later drift silently after the result pill fades; real subtitle engine announces then aligns fixture metadata |
| `m12` | killed in independent sample | subtitle selected before engine installation remains inactive even when the same path is selected again |
| `m13` | killed in independent sample | subtitle off then new selection cannot inherit an old announcement hide; subtitle off then new selection cannot inherit an old result hide; subtitle automatic source priority retires on preferred audio; subtitle pending filter removal across subtitle change preserves the lifecycle queue |
| `m14` | killed in addendum | Non-equivalent. Startup resets the session singleton, but an outgoing saved public stepper callback can write -1500 after that reset while the incoming font lookup is suspended before loadAll reads session memory. Its returned settings snapshot applies -1.500 native sub-delay, suppresses listening, and a public track-reset callback releases the real ladder. The >0 mutation fails that native assertion. |
| `m15` | killed in independent sample | subtitle style timing feedback invalidates a held real alignment before its offset can win |
| `m16` | killed in independent sample | subtitle saved stepper manual callback cancels a held real alignment and hides checking; subtitle manual hide keeps a later offset-suppressed selection quiet when its ladder is rearmed; subtitle saved line manual callback cancels a held real alignment and hides checking; subtitle content replacement clears timing and path but a saved line callback targets the new playback |
| `m17` | killed in independent sample | subtitle content replacement clears timing and path but a saved line callback targets the new playback; subtitle timing is session only while appearance migrates and persists; subtitle timing reset clears session and skips nonnative property; subtitle timing reset clears session and native property |
| `m18` | killed in independent sample | subtitle stepper updates session and native delay and dismisses; subtitle line picker updates session and native delay and dismisses |
| `m19` | killed in independent sample | subtitle content replacement clears timing and path but a saved line callback targets the new playback; subtitle line picker updates session and native delay and dismisses |
| `m20` | killed in independent sample | subtitle stepper clamps callback -4000000 before native and rendered writes; subtitle stepper clamps callback 4000000 before native and rendered writes |

Final independent sample closure: **18 killed /18 non-equivalent (100%)**;
`m7` and `m8` excluded by the source invariants above. First sweep totals remain
151 kills /12 equivalent /2 raw-Android pending /2 dormant /3 invalid; the
additional sample candidates supply two new kills and two proven equivalents.
The 21-declaration matrix and 33-reference ledger remain exhaustive. Every prior
test name/assertion is preserved; 72 cases total. New-case original witnesses:

| New behaviour | Original assertion-failing mutation |
|---|---|
| cumulative real verification clamps native/session/overlay at +3600000 | `step0b/m4.patch`, `m4.jsonl` |
| cold negative session offset reaches native load and suppresses listening | `step0b/m14.patch`, `m14.jsonl` |

Both controls bracket the detached original application, byte-identical to
`122896451` (`bd671bd09` lib/); final case-file hashes and commands are recorded
in `step0b/results.json`. Development controls 1–8 are excluded: an initial
self-copy/no-matching case, one-shot barrier not rearmed, insufficient cue overlap,
and a mistaken fixture timestamp stride. These were fixture construction issues;
final native/session/UI assertions are retained. Fresh additions-only baseline
versus Step 0: **13,465 success /13 failure /28 load error /20 skip**, exactly
two passing additions and zero changed/missing/new skips; evidence
`step0b/baseline*`. No allowlist change. CI remains P8 until production Step 1.


## Phase 9 Step 1 — frozen production split (2026-10-14)

The applied manifest classifies **807 original spans: 21 moved, 785 retained,
one patched constructor**. The combined
`lib/features/video_player/presentation/legacy_video_player/vp_subtitle_auto_sync.dart`
is **305 lines**; facade **16,829 →16,603** (size ratchet updated). All 33
retained occurrences retain their statement positions. Settings, external path,
overlay flag, notifier allocation/disposal and fade cache remain State-owned.
The exact 14-member live Host forwards through the frozen adapter and `_vpSetState`;
its constructor and five false/null initializers perform no Host read or effect.
State construction appends `_subtitleSync` after `_pip`. Both teardown protocols,
external-path snapshot, live player-position callback, PiP adapter and all 18
earlier destinations are preserved by exhaustive token/body/binding comparison.
Original comments retain their frozen span ownership.

CI now selects P9 for current/self-test and both analyzer arguments, retains
P1–P7 named histories, adds P8 at `0df6ccd4e`, and retains S/S2/S2b proofs and
the harness define. All six subtitle suites are registered. Theme manifest,
rendered boundaries and all three source-guard lists cover the new destination.
No moved legacy source anchor required a textual retarget; the existing
validating reader discovers/chains applied P9 without weakening any assertion.
The frozen facade import list exposes three already-probed unused imports;
the global warning allowlist records exactly those identities. Earlier analyzer
mappings/maxima and the P9 inventory are preserved.

Step-1 verification: **82 focused subtitle/theme cases PASS** (72 original
behaviours plus ten unchanged theme guards); **14 mechanical jobs PASS**
(current P9, P1–P8 historical checks, S/S2/S2b, size/architecture/negatives).
Scoped CI analysis and the warning allowlist PASS; the P9 comparator observes
**104 scoped diagnostics, zero additions**, including infos and multiplicity.
Formatting is idempotent; production files are byte-identical to the Step-T
formatted proof (three AST-optional commas inserted, none deleted, zero
format-induced diagnostic changes). Evidence `p9/step1/`. No app bug fix,
dependency change or release build here. The clean-tree gate follows this commit.


## Phase 9 clean-tree gate (2026-10-14)

Tested production checkpoint `a2be68e2d` on a clean, stable tree. Full fresh
`suite_evidence.py run vplayer/p9/gate/flutter-gate --no-pub
--dart-define=DEBRIFY_VP_TEST_HOOKS=true` has exactly the Step-0b baseline
identities/outcomes: **13,465 success /13 failure /28 load error /20 skip**;
zero changed, added, missing, fixed or newly skipped identities. Same SDK/flags.
No flake stabilization, failure recording or test allowlist change.

**42 mechanical jobs PASS:** all 26 other Dart manifest self-tests, P9 universal
self-tests plus exhaustive all-retained original comparison, current P9,
P1–P8 named same-revision historical checks, Kotlin compiled/ownership/history
self-tests, S and S2/S2b proofs, size, architecture and architecture negatives.
All primary/nested parser runs use isolated copied packages under the worktree's
`.dart_tool/vplayer_parser/`; copied kernels removed and routing audited.
CI-scope analysis/allowlist PASS, P9 comparator **104 scoped occurrences /zero
additions**, infos and multiplicity included. CI formatting plus the theme guard
is idempotent. Size **3003 checked /140 ratcheted**; migrated architecture passes.

Both **`flutter build apk --release --no-pub`** and
**`flutter build macos --release --no-pub`** complete successfully under nice19.
No run/install/device command, production change during the gate, dependency
change, push, merge or branch switch. Evidence `p9/gate/completion.json`,
`checks-results.json`, `run-results.json`, `suite-strict.json`, analyzer/format
logs, `build-results.json` and both complete build logs.

Device checklist remains honest: native audio DSP/decoded alignment, raw
mobile/web capabilities and Android compressed passthrough stop/PCM rearm need
physical target validation; none is claimed from these fake-platform tests.
The two session-persistence catch diagnostics and five legacy-sheet paths remain
dormant as previously classified. M2 follows phases 9–11; no M2 work here.

## Phase 10 S2c — renderer rejection seam checkpoint (2026-10-14)

Application base `5c7b704bd`; approved design `e1e73b811`. Only the first Android
predicate in `_setSubtitleTrackWithDiagnostics` changes to
`VpS2Hooks.isAndroid`. The preceding current-attempt guard, TV exemption,
`requiresNativeSubtitleRendering(track)` and renderer-mode comparison retain
short-circuit order. S, the hook/getter/installer and the accepted S2/S2b ledger
are unchanged. No new hook, installer, production collaborator or behavior fix.

`dev/tool/dart_moves/vplayer_p10_seam.json` is an exhaustive checkpoint against
the phase-9 merge: **789 spans, 788 retained, one patched, zero moves/scaffolds**.
Its single exact token patch includes the Android/TV guard context and count 1;
the whole declaration is compared, and history protects every earlier
video-player destination. Current CI and analyzer-manifest inputs use this
checkpoint with P9's unchanged inventory, plus P9 `--at 5c7b704bd`. The accepted
P8 checkpoint remains frozen byte-for-byte; S2/S2b proofs are preserved.
The S proof's summary now names its own accepted scaffolding ledger, allowing
an all-retained current checkpoint without changing its assertions.

Independent source/default/installation guard: **31 negatives**, all 23 prior
ones plus eight for S2c. Existing guard-test names/assertions remain; the source
guard additionally requires the S2c count and all eight new negative receipts.
Actual hook and guard bodies extracted from the parser run with controlled
native predicates/operands. Five complete controls pass: debug with flag,
without flag, assertions disabled, profile, and compiled release. The 432
combined truth-table cases pin nullable/current validation, native/default or
live/partial override selection, once-only calls, TV/rendering/mode order and
short-circuiting. Each runtime mutant below compiles and fails a checked
assertion; none is credited from a load/compile error.

| S2c site mutation | Assertion-failing runtime witness under `p10/s2c/` |
| --- | --- |
| Override bypassed with raw `Platform.isAndroid` | `negative-override-bypassed.log` (reader/order) |
| Android getter replaced with iOS | `negative-wrong-predicate.log` (result/order) |
| Android read duplicated | `negative-predicate-twice.log` (once-only order) |
| TV operand evaluated before Android | `negative-operand-order.log` (short-circuit order) |
| TV exemption bypassed | `negative-TV-bypassed.log` (result/order) |
| Preceding current guard removed | `negative-current-guard-removed.log` (result/order) |
| Native-rendering predicate bypassed | `negative-rendering-bypassed.log` (result/order) |
| Renderer comparison inverted | `negative-mode-inverted.log` (result) |

Evidence `p10/s2c/`: `S.json`, `S2-S2b-S2c.json`, current/P9/S2b historical
checks, passing CI checkpoint universal self-test, commands/results,
isolated-parser routing and runtime extracted bodies,
controls and witnesses. Serialized `suite_evidence.py` runs on the existing
S/S2 guard files pass **7/7 each** with the compile-time flag true and false;
both complete and their tested trees remain stable. Original/current scoped
analysis has **104 identical diagnostic occurrences**, including infos and
multiplicity; zero additions, zero formatting diagnostics or comma edits.
Guard-test analysis, format/idempotence, size, architecture and diff pass.
The unchanged facade remains 16,603 lines; no size allowance or pubspec change.

Two preliminary rejected attempts are archived uncredited: a summary assumed
new scaffolding in the current ledger, and one negative matched both identical
current-check statements. Corrected summary and exact renderer context preserve
all assertions; complete final runs pass. Step T, Step 0, production moves,
full-suite gate and builds are deferred until independent S2c review. Android
bitmap rejection/acceptance and TV exemption are Step-0 caller cases; decoded
bitmap rendering stays device-pending. Final revision: `p10/s2c/commit.json`.


## Phase 10 Step T — subtitle apply draft and approved Host correction

Original application checkpoint: S2c `a2e034cb3`; P9 historical merge
`5c7b704bd`. Claude accepted `vp-rev10s2c` with no P1/P2/P3 and approved
`p10/stepT/host-correction-proposal.json` (plan checkpoint `2adc21ec2`). The
frozen Host is 18 names /21 declarations, with a live `isAndroid` getter
forwarding exactly to `VpS2Hooks.isAndroid` and four registered complete chains.
The destination has no facade import.

The evidence-only materialization classifies all 789 original spans: 782
retained, five moved and two patched (State constructor and PiP Host adapter).
The 23 retained references comprise 22 ordinary substitutions and the one
counted PiP adapter rewrite. Both diagnostics fields and the correction notifier
remain State-owned; reset/disposal statements and resource ordering remain in
place. The constructor appends the inert collaborator after `_subtitleSync`.
All 19 earlier destinations are derived from historical manifests and protected.
The formatted hypothetical destination is 223 lines; the facade is 16,477 lines.
Application code and current CI still select the accepted S2c checkpoint.

`p10/stepT/probe/`, `formatted/`, `remeasured.json` and the draft manifest freeze
imports, member order, Host/adapter bodies and substitutions. Formatting inserts
one AST-optional trailing comma in the destination and none in the facade;
zero token differences, idempotence and zero introduced diagnostic identities.
The original root and probe each have 104 scoped diagnostics; the strict original
has 176. The P10 inventory preserves every P1–P9 identity and canonical mapping;
no receiver-induced async-context diagnostic in the five moved methods.
`format-diagnostics.json`, `async-context-identities.json` and analyzer logs record
identity correspondence by declaration, not line counts.

Real-config negatives cover live/cached platform and player getters, all four
chain registrations, shared field/setter/increment ownership, captured locals,
constructor effects, PiP projection, teardown preservation, notifier identity
and facade imports. The new fixture is registered in the universal Dart checker
self-test. Commands and completed results are archived in `p10/stepT/`; the 36
unchanged prerequisite checks (26 existing Dart manifests, P1–P9 `--at`, Kotlin)
are reused from `independent-results.json`.


## Phase 10 Step 0 — original subtitle apply and diagnostics

Application ORIGINAL: independently accepted S2c `a2e034cb3`; tooling checkpoint
`1a51002e7`. No application or pubspec change. All tests call the original menu,
subscription, initialization, channel guide or PiP paths. No private State access,
fabricated attempt objects or source-text behavior assertions. Shared H pending
activities remain separate from completion; native/player/50 ms/poll/storage
barriers assert the intermediate state before release. Synthetic HTTP only.

### Coverage matrix

| Original responsibility | Executable boundary / evidence |
|---|---|
| `_waitForSubtitleTracks` | Real startup preferences caller: auto/no/empty IDs ignored; arrival on first poll; exactly fifty 100 ms polls; content token retirement. Startup is deliberately held before autosave registration. `wait_test`. |
| `_setNativeSubtitleVisibilityForTrack` | Non-native/text/bitmap/image/external; request-level visibility calls; previous bitmap restoration; failed visibility retry; iOS PiP entry/start/restore via existing S2 original callers. `contract`, `renderer`, existing `pip_ios`. |
| `_setSubtitleTrackWithDiagnostics` | Five boundary stages × reset/profile/dispose/replacement (20 cases); success/codec failures, exact 50 ms turn and no turn after immediate failure; Android directSurface rejection/directMediaCodec acceptance/TV exemption (8 cases); automatic live guard after visibility versus manual addon’s null callback. `boundaries`, `late_failures`, `callers`, `contract`, `renderer`. |
| `_handleSubtitleApplyFailure` | Old log acts on current B; delayed A exception rejected; admitted A rollback continues across B; same-A log then exception handled once; previous auto/same/no/addon/bitmap and failed fallback; repeated/held-turn menu correction; both notifier values after disposal. `races`, `contract`, `disposed_menu`. |
| `_showSubtitleFailureMessage` | Mounted floating four-second snackbar replaces previous message; renderer/load/missing-track/native/empty-codec/outer unexpected diagnostic-sink failure messages; post-disposal suppression. `contract`, `renderer`, `late_failures`. |
| Persistence / completer identities | Successful/failed optimistic write × same/reset/profile/dispose; physical values before release; newest matching completer and both release orders; outgoing map written into incoming physical profile; unrelated entries in A/B; active attempt cleared before later audio write. `persistence`. |
| Retained callers / early windows | Startup stored/no-preference/off/language/foreign-off/forced paths and stored rejection source; live audio change; public off, embedded/addon callbacks; four TV/channel opens; PiP adapter. Early startup held during track/default restoration before autosave registration; saved callbacks cross disposal. `callers`, existing `subtitle_edges`, `wait`, `disposed_menu`. |
| Dormant compatibility | Unified menu’s constant-true return precedes TracksSheet installation: one legacy apply and two old addon error-message references. Only notifier listener is dormant; assignments are observable after disposal and are tested. Exact bodies remain frozen. |
| Device-pending | Physical native decoder/bitmap rendering and platform PiP presentation remain device checks. Property protocols, rejection policy, callback/owner timing and UI outcomes are executable; no device parity claim. |

The systematic original AST inventory enumerates **152 statement/branch/literal
points** in five moves (including both counter increments) and **23 retained
executable occurrences**. First sweep: 91 assertion kills, 24 survivors, 35
invalid candidates and two uncredited runtime/timeout attempts. Closure: 19
additional assertion kills and seven original-caller equivalences. Final: **110
assertion kills /110 non-equivalent valid candidates**, seven equivalents and
35 flow/type-invalid candidates; no compile/load error or timeout earns kill
credit. Parent expression/snapshot/branch behavior is independently covered for
invalid declaration-removal candidates. Retained-reference sweep: **20/20 live
references assertion-killed**, three dormant legacy references frozen.

`p10/step0/inventory-full.json`, `mutation-plan.json`, `mutation-final-results.json`,
`reference-final-results.json`, patches and per-mutation JSON/stderr logs contain
exact offsets (UTF-16), candidates, commands, completed events, test identities
and hashes. `equivalence-source-audit.json` and adjacent original source context
record the producer/guard invariants. Tests were strengthened for request counts,
exact diagnostics, the post-visibility guard’s false result, failed visibility
retry, current completer ownership and still-open parent menu selection.
Initial uncredited attempts remain separate from final witnesses.

### Systematic mutation table (S2c application code)

| Point | Original declaration / line / kind | Final fate | Assertion witness / audit |
|---|---|---|---|
| `p000` | `_waitForSubtitleTracks`:3891 / integer | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p001` | `_waitForSubtitleTracks`:3891 / operator | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p002` | `_waitForSubtitleTracks`:3891 / integer | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p003` | `_waitForSubtitleTracks`:3891 / postfix | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p004` | `_waitForSubtitleTracks`:3892 / branch | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p005` | `_waitForSubtitleTracks`:3892 / operator | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p006` | `_waitForSubtitleTracks`:3892 / return | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p007` | `_waitForSubtitleTracks`:3893 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p008` | `_waitForSubtitleTracks`:3895 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p009` | `_waitForSubtitleTracks`:3896 / operator | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p010` | `_waitForSubtitleTracks`:3896 / operator | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p011` | `_waitForSubtitleTracks`:3896 / operator | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p012` | `_waitForSubtitleTracks`:3896 / string | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p013` | `_waitForSubtitleTracks`:3896 / operator | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p014` | `_waitForSubtitleTracks`:3896 / string | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p015` | `_waitForSubtitleTracks`:3898 / branch | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p016` | `_waitForSubtitleTracks`:3899 / return | assertion-killed | subtitle track polling accepts a real arrival while ignoring placeholders |
| `p017` | `_waitForSubtitleTracks`:3901 / statement | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p018` | `_waitForSubtitleTracks`:3901 / integer | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders |
| `p019` | `_setNativeSubtitleVisibilityForTrack`:3909 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p020` | `_setNativeSubtitleVisibilityForTrack`:3910 / branch | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p021` | `_setNativeSubtitleVisibilityForTrack`:3910 / return | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p022` | `_setNativeSubtitleVisibilityForTrack`:3911 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p023` | `_setNativeSubtitleVisibilityForTrack`:3912 / operator | assertion-killed | subtitle Android bitmap codec renderer directMediaCodec TV exempt selection preserves rejection and native visibility |
| `p024` | `_setNativeSubtitleVisibilityForTrack`:3913 / operator | assertion-killed | PiP iOS entry prepares native subtitles once, sends its distinct handle and leaves auto-enter unarmed |
| `p025` | `_setNativeSubtitleVisibilityForTrack`:3913 / operator | assertion-killed | PiP iOS entry prepares native subtitles once, sends its distinct handle and leaves auto-enter unarmed |
| `p026` | `_setNativeSubtitleVisibilityForTrack`:3914 / statement | assertion-killed | subtitle Android bitmap codec renderer directMediaCodec TV exempt selection preserves rejection and native visibility |
| `p027` | `_setNativeSubtitleVisibilityForTrack`:3915 / string | assertion-killed | subtitle Android bitmap codec renderer directMediaCodec TV exempt selection preserves rejection and native visibility |
| `p028` | `_setNativeSubtitleVisibilityForTrack`:3916 / conditional | assertion-killed | subtitle apply native success persists the matching identity after its diagnostic turn |
| `p029` | `_setNativeSubtitleVisibilityForTrack`:3916 / string | assertion-killed | subtitle Android bitmap codec renderer directMediaCodec TV exempt selection preserves rejection and native visibility |
| `p030` | `_setNativeSubtitleVisibilityForTrack`:3916 / string | assertion-killed | subtitle apply native success persists the matching identity after its diagnostic turn |
| `p031` | `_setSubtitleTrackWithDiagnostics`:3929 / branch | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `p032` | `_setSubtitleTrackWithDiagnostics`:3929 / operator | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p033` | `_setSubtitleTrackWithDiagnostics`:3929 / operator | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p034` | `_setSubtitleTrackWithDiagnostics`:3929 / null | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p035` | `_setSubtitleTrackWithDiagnostics`:3929 / return | equivalent-original-callers | Original producer invariants; equivalence-source-audit.json |
| `p036` | `_setSubtitleTrackWithDiagnostics`:3929 / boolean | equivalent-original-callers | Original producer invariants; equivalence-source-audit.json |
| `p037` | `_setSubtitleTrackWithDiagnostics`:3930 / branch | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p038` | `_setSubtitleTrackWithDiagnostics`:3930 / operator | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p039` | `_setSubtitleTrackWithDiagnostics`:3930 / operator | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p040` | `_setSubtitleTrackWithDiagnostics`:3930 / operator | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p041` | `_setSubtitleTrackWithDiagnostics`:3933 / operator | assertion-killed | subtitle Android image renderer directMediaCodec phone selection preserves rejection and native visibility |
| `p042` | `_setSubtitleTrackWithDiagnostics`:3935 / statement | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p043` | `_setSubtitleTrackWithDiagnostics`:3936 / string | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p044` | `_setSubtitleTrackWithDiagnostics`:3938 / statement | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p045` | `_setSubtitleTrackWithDiagnostics`:3939 / interpolated-string | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p046` | `_setSubtitleTrackWithDiagnostics`:3940 / string | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p047` | `_setSubtitleTrackWithDiagnostics`:3942 / return | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p048` | `_setSubtitleTrackWithDiagnostics`:3942 / boolean | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility |
| `p049` | `_setSubtitleTrackWithDiagnostics`:3944 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p050` | `_setSubtitleTrackWithDiagnostics`:3944 / prefix | equivalent-original-callers | Original producer invariants; equivalence-source-audit.json |
| `p051` | `_setSubtitleTrackWithDiagnostics`:3945 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p052` | `_setSubtitleTrackWithDiagnostics`:3953 / statement | assertion-killed | subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `p053` | `_setSubtitleTrackWithDiagnostics`:3956 / statement | assertion-killed | subtitle saved menu callback after disposal throws while clearing the corrected notifier as-is |
| `p054` | `_setSubtitleTrackWithDiagnostics`:3956 / null | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p055` | `_setSubtitleTrackWithDiagnostics`:3959 / statement | assertion-killed | subtitle apply native success persists the matching identity after its diagnostic turn |
| `p056` | `_setSubtitleTrackWithDiagnostics`:3960 / branch | assertion-killed | subtitle previous addon identity and external path restore together after an embedded failure |
| `p057` | `_setSubtitleTrackWithDiagnostics`:3960 / operator | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p058` | `_setSubtitleTrackWithDiagnostics`:3960 / operator | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p059` | `_setSubtitleTrackWithDiagnostics`:3960 / null | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p060` | `_setSubtitleTrackWithDiagnostics`:3960 / return | assertion-killed | subtitle previous addon identity and external path restore together after an embedded failure |
| `p061` | `_setSubtitleTrackWithDiagnostics`:3960 / boolean | assertion-killed | subtitle startup automatic apply superseded by a manual choice returns false to the original restore diagnostic |
| `p062` | `_setSubtitleTrackWithDiagnostics`:3961 / statement | assertion-killed | subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `p063` | `_setSubtitleTrackWithDiagnostics`:3963 / statement | assertion-killed | subtitle late track exception after profile obeys only the original failure admission guard |
| `p064` | `_setSubtitleTrackWithDiagnostics`:3964 / interpolated-string | assertion-killed | subtitle late track exception after profile obeys only the original failure admission guard |
| `p065` | `_setSubtitleTrackWithDiagnostics`:3965 / interpolated-string | assertion-killed | subtitle late track exception after profile obeys only the original failure admission guard |
| `p066` | `_setSubtitleTrackWithDiagnostics`:3966 / interpolated-string | assertion-killed | subtitle late track exception after profile obeys only the original failure admission guard |
| `p067` | `_setSubtitleTrackWithDiagnostics`:3968 / statement | assertion-killed | subtitle late track exception after profile obeys only the original failure admission guard |
| `p068` | `_setSubtitleTrackWithDiagnostics`:3969 / return | assertion-killed | subtitle failed apply falls back to no for previous 2 selection |
| `p069` | `_setSubtitleTrackWithDiagnostics`:3969 / boolean | assertion-killed | subtitle late track exception after profile obeys only the original failure admission guard |
| `p070` | `_setSubtitleTrackWithDiagnostics`:3975 / statement | assertion-killed | subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `p071` | `_setSubtitleTrackWithDiagnostics`:3975 / integer | assertion-killed | subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `p072` | `_setSubtitleTrackWithDiagnostics`:3976 / branch | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn |
| `p073` | `_setSubtitleTrackWithDiagnostics`:3976 / return | assertion-killed | subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `p074` | `_setSubtitleTrackWithDiagnostics`:3976 / boolean | assertion-killed | subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `p075` | `_setSubtitleTrackWithDiagnostics`:3978 / statement | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn |
| `p076` | `_setSubtitleTrackWithDiagnostics`:3978 / boolean | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn |
| `p077` | `_setSubtitleTrackWithDiagnostics`:3979 / return | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p078` | `_setSubtitleTrackWithDiagnostics`:3979 / boolean | assertion-killed | subtitle saved menu callback after disposal throws while clearing the corrected notifier as-is |
| `p079` | `_handleSubtitleApplyFailure`:3986 / branch | assertion-killed | subtitle old decoder log rolls the current accepted B attempt back as-is |
| `p080` | `_handleSubtitleApplyFailure`:3986 / operator | equivalent-original-callers | Original producer invariants; equivalence-source-audit.json |
| `p081` | `_handleSubtitleApplyFailure`:3986 / operator | equivalent-original-callers | Original producer invariants; equivalence-source-audit.json |
| `p082` | `_handleSubtitleApplyFailure`:3987 / operator | assertion-killed | subtitle late track exception after profile obeys only the original failure admission guard |
| `p083` | `_handleSubtitleApplyFailure`:3988 / operator | assertion-killed | subtitle late track exception after profile obeys only the original failure admission guard |
| `p084` | `_handleSubtitleApplyFailure`:3989 / return | assertion-killed | subtitle delayed A apply exception is rejected after B becomes current |
| `p085` | `_handleSubtitleApplyFailure`:3991 / statement | assertion-killed | subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `p086` | `_handleSubtitleApplyFailure`:3991 / boolean | assertion-killed | subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `p087` | `_handleSubtitleApplyFailure`:3992 / statement | equivalent-original-callers | Original producer invariants; equivalence-source-audit.json |
| `p088` | `_handleSubtitleApplyFailure`:3992 / boolean | equivalent-original-callers | Original producer invariants; equivalence-source-audit.json |
| `p089` | `_handleSubtitleApplyFailure`:3993 / statement | assertion-killed | subtitle admitted rollback clears the active attempt before a later audio preference write |
| `p090` | `_handleSubtitleApplyFailure`:3993 / null | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p091` | `_handleSubtitleApplyFailure`:3995 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p092` | `_handleSubtitleApplyFailure`:3996 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p093` | `_handleSubtitleApplyFailure`:3996 / operator | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn |
| `p094` | `_handleSubtitleApplyFailure`:3997 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p095` | `_handleSubtitleApplyFailure`:3997 / conditional | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn |
| `p096` | `_handleSubtitleApplyFailure`:3997 / operator | assertion-killed | subtitle failed apply falls back to no for previous auto selection |
| `p097` | `_handleSubtitleApplyFailure`:3997 / operator | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn |
| `p098` | `_handleSubtitleApplyFailure`:3997 / string | assertion-killed | subtitle failed apply falls back to no for previous auto selection |
| `p099` | `_handleSubtitleApplyFailure`:4000 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p100` | `_handleSubtitleApplyFailure`:4000 / operator | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn |
| `p101` | `_handleSubtitleApplyFailure`:4002 / statement | assertion-killed | subtitle late text failure restores a previously selected bitmap with native visibility enabled |
| `p102` | `_handleSubtitleApplyFailure`:4003 / statement | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn |
| `p103` | `_handleSubtitleApplyFailure`:4005 / statement | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `p104` | `_handleSubtitleApplyFailure`:4005 / boolean | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `p105` | `_handleSubtitleApplyFailure`:4006 / statement | assertion-killed | subtitle rollback second native failure preserves one original codec message |
| `p106` | `_handleSubtitleApplyFailure`:4007 / interpolated-string | assertion-killed | subtitle rollback second native failure preserves one original codec message |
| `p107` | `_handleSubtitleApplyFailure`:4010 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p108` | `_handleSubtitleApplyFailure`:4011 / statement | assertion-killed | subtitle failed rollback visibility retries no-track visibility before applying the no track |
| `p109` | `_handleSubtitleApplyFailure`:4012 / statement | assertion-killed | subtitle rollback second native failure preserves one original codec message |
| `p110` | `_handleSubtitleApplyFailure`:4020 / statement | assertion-killed | subtitle previous addon identity and external path restore together after an embedded failure |
| `p111` | `_handleSubtitleApplyFailure`:4020 / conditional | assertion-killed | subtitle previous addon identity and external path restore together after an embedded failure |
| `p112` | `_handleSubtitleApplyFailure`:4022 / null | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p113` | `_handleSubtitleApplyFailure`:4023 / statement | assertion-killed | subtitle previous addon identity and external path restore together after an embedded failure |
| `p114` | `_handleSubtitleApplyFailure`:4024 / conditional | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `p115` | `_handleSubtitleApplyFailure`:4024 / null | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p116` | `_handleSubtitleApplyFailure`:4026 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p117` | `_handleSubtitleApplyFailure`:4027 / branch | assertion-killed | subtitle previous addon identity and external path restore together after an embedded failure |
| `p118` | `_handleSubtitleApplyFailure`:4027 / operator | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `p119` | `_handleSubtitleApplyFailure`:4027 / operator | assertion-killed | subtitle previous addon identity and external path restore together after an embedded failure |
| `p120` | `_handleSubtitleApplyFailure`:4027 / null | assertion-killed | subtitle apply native success persists the matching identity after its diagnostic turn |
| `p121` | `_handleSubtitleApplyFailure`:4028 / statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p122` | `_handleSubtitleApplyFailure`:4028 / interpolated-string | assertion-killed | subtitle previous addon identity and external path restore together after an embedded failure |
| `p123` | `_handleSubtitleApplyFailure`:4030 / statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p124` | `_handleSubtitleApplyFailure`:4030 / conditional | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `p125` | `_handleSubtitleApplyFailure`:4030 / string | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `p126` | `_handleSubtitleApplyFailure`:4036 / branch | assertion-killed | subtitle rollback waits for successful optimistic persistence across same content |
| `p127` | `_handleSubtitleApplyFailure`:4036 / operator | assertion-killed | subtitle initialization reaches the forced original apply caller |
| `p128` | `_handleSubtitleApplyFailure`:4037 / statement | assertion-killed | subtitle rollback waits for successful optimistic persistence across same content |
| `p129` | `_handleSubtitleApplyFailure`:4038 / statement | assertion-killed | subtitle rollback waits for successful optimistic persistence across same content |
| `p130` | `_handleSubtitleApplyFailure`:4043 / branch | assertion-killed | subtitle saved menu callback after disposal throws while clearing the corrected notifier as-is |
| `p131` | `_handleSubtitleApplyFailure`:4043 / return | assertion-killed | subtitle rollback track held across dispose preserves the original admitted work |
| `p132` | `_handleSubtitleApplyFailure`:4044 / statement | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `p133` | `_handleSubtitleApplyFailure`:4045 / statement | assertion-killed | subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `p134` | `_handleSubtitleApplyFailure`:4046 / statement | assertion-killed | subtitle saved menu callback after disposal throws while clearing the corrected notifier as-is |
| `p135` | `_handleSubtitleApplyFailure`:4048 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p136` | `_handleSubtitleApplyFailure`:4049 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p137` | `_handleSubtitleApplyFailure`:4049 / conditional | assertion-killed | subtitle empty codec failure uses the generic diagnostic and restores native visibility |
| `p138` | `_handleSubtitleApplyFailure`:4049 / operator | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p139` | `_handleSubtitleApplyFailure`:4049 / operator | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p140` | `_handleSubtitleApplyFailure`:4049 / null | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p141` | `_handleSubtitleApplyFailure`:4050 / string | assertion-killed | subtitle empty codec failure uses the generic diagnostic and restores native visibility |
| `p142` | `_handleSubtitleApplyFailure`:4051 / interpolated-string | assertion-killed | subtitle rollback second native failure preserves one original codec message |
| `p143` | `_handleSubtitleApplyFailure`:4052 / statement | assertion-killed | subtitle empty codec failure uses the generic diagnostic and restores native visibility |
| `p144` | `_handleSubtitleApplyFailure`:4053 / statement | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn |
| `p145` | `_handleSubtitleApplyFailure`:4054 / interpolated-string | assertion-killed | subtitle empty codec failure uses the generic diagnostic and restores native visibility |
| `p146` | `_showSubtitleFailureMessage`:4059 / branch | assertion-killed | subtitle failure replaces the previous snackbar with a floating four-second message |
| `p147` | `_showSubtitleFailureMessage`:4059 / return | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p148` | `_showSubtitleFailureMessage`:4060 / declaration-statement | invalid-candidate | Flow/type-invalid removal/replacement; no kill credit; parent behavior separately exercised |
| `p149` | `_showSubtitleFailureMessage`:4061 / statement | assertion-killed | subtitle failure replaces the previous snackbar with a floating four-second message |
| `p150` | `_showSubtitleFailureMessage`:4062 / statement | assertion-killed | subtitle failure replaces the previous snackbar with a floating four-second message |
| `p151` | `_showSubtitleFailureMessage`:4066 / integer | assertion-killed | subtitle failure replaces the previous snackbar with a floating four-second message |

Seven equivalences: initial false-return arm is unreachable because every pure
non-null current closure is checked synchronously by its caller immediately
before entry (the post-await check is non-equivalent); the signed generation
sequence is unobserved with identity admission preserved; handled stamping and
both single-token OR-to-AND rewrites preserve admission under original producers.
Dart precedence matters: the rewrites are `(handled && differentObject) ||
differentGeneration` and `handled || (differentObject && differentGeneration)`.
No simplification or counter change is made. Current-object/generation capture,
flags, comparisons and every dormant statement remain token-frozen.

### Frozen retained-occurrence ledger

| Occurrence | Original caller / line | Fate / witness |
|---|---|---|
| `r01` | `_bindPlayerInstanceSubscriptions`:2667 | assertion-killed — subtitle apply native success persists the matching identity after its diagnostic turn |
| `r02` | `_goToNextEpisode`:5066 | assertion-killed — subtitle magic next open uses its diagnostic no-track caller and preserves rollback |
| `r03` | `_switchToStremioTvChannel`:8721 | assertion-killed — subtitle Stremio guide open uses its diagnostic no-track caller and preserves rollback |
| `r04` | `_goToChannelById`:8933 | assertion-killed — subtitle guide channel open uses its diagnostic no-track caller and preserves rollback |
| `r05` | `_goToNextChannel`:9062 | assertion-killed — subtitle next channel open uses its diagnostic no-track caller and preserves rollback |
| `r06` | `_showTracksSheet`:14888 | dormant-unified-menu-compatibility — constant kUnifiedPlayerMenuEnabled returns before TracksSheet installation; no public caller of the old addon helper; frozen unchanged body/token proof |
| `r07` | `_menuSubtitlesOff`:15049 | assertion-killed — superseded subtitle apply cannot roll back newer accepted selection |
| `r08` | `_menuSelectEmbeddedSubtitle`:15065 | assertion-killed — subtitle failure replaces the previous snackbar with a floating four-second message |
| `r09` | `_menuSelectEmbeddedSubtitle`:15070 | assertion-killed — subtitle apply native success persists the matching identity after its diagnostic turn |
| `r10` | `_menuSelectAddonSubtitle`:15093 | assertion-killed — subtitle addon download failure uses the load-failure message caller without native apply or persistence |
| `r11` | `_menuSelectAddonSubtitle`:15115 | assertion-killed — subtitle addon unexpected diagnostic sink failure reaches its outer failure-message caller |
| `r12` | `_applyStremioSubtitleFromTracksSheet`:15129 | dormant-unified-menu-compatibility — constant kUnifiedPlayerMenuEnabled returns before TracksSheet installation; no public caller of the old addon helper; frozen unchanged body/token proof |
| `r13` | `_applyStremioSubtitleFromTracksSheet`:15150 | dormant-unified-menu-compatibility — constant kUnifiedPlayerMenuEnabled returns before TracksSheet installation; no public caller of the old addon helper; frozen unchanged body/token proof |
| `r14` | `_restoreTrackPreferences`:15278 | assertion-killed — subtitle old track poll stops on content token change before touching incoming preferences |
| `r15` | `_restoreTrackPreferences`:15412 | assertion-killed — subtitle stored preference rejection preserves its restore-specific diagnostic source |
| `r16` | `_refreshSubtitleAudioPolicy`:15567 | assertion-killed — subtitle live audio policy uses the off apply caller before source priority reselects |
| `r17` | `_applyDefaultSubtitleLanguage`:15595 | assertion-killed — subtitle initialization reaches the foreign off original apply caller |
| `r18` | `_applyDefaultSubtitleLanguage`:15637 | assertion-killed — subtitle initialization reaches the no preference original apply caller |
| `r19` | `_applyDefaultSubtitleLanguage`:15648 | assertion-killed — subtitle initialization reaches the off original apply caller |
| `r20` | `_applyDefaultSubtitleLanguage`:15676 | assertion-killed — subtitle initialization reaches the language original apply caller |
| `r21` | `_applyForcedSubtitle`:15717 | assertion-killed — subtitle initialization reaches the forced original apply caller |
| `r22` | `_applyExternalSubtitleTrack`:15818 | assertion-killed — subtitle previous addon identity and external path clear when native rollback fails |
| `r23` | `_VpPipLifecycleHostAdapter`:16181 | assertion-killed — PiP iOS entry prepares native subtitles once, sends its distinct handle and leaves auto-enter unarmed |

The outer addon catch is reached by a failing public debugPrint sink while a
native apply error is being diagnosed; this pins its unexpected-error fallback
without injecting a private attempt or modifying production. Stored rejection
pins the diagnostic source rather than allowing a later default selection to
mask the missing stored call. Foreign-off startup pins its separate native
request; three serial original controls pass before its mutation is credited.

### Final per-test assertion witnesses

Each of the 87 new cases passes on unmodified S2c and is killed by a valid original
application mutation. `test-witnesses/` records complete final-file runs, patches
and hashes; `per-test-witness-ledger.json` maps each test. The shared helper entry
mutations supplement the point-specific sweep; they do not replace it.

| Test | Original assertion-failing witness |
|---|---|
| subtitle apply visibility held across reset preserves the original admitted work | `apply-entry` |
| subtitle apply visibility held across profile preserves the original admitted work | `apply-entry` |
| subtitle apply visibility held across dispose preserves the original admitted work | `apply-entry` |
| subtitle apply visibility held across replacement preserves the original admitted work | `apply-entry` |
| subtitle apply track held across reset preserves the original admitted work | `apply-entry` |
| subtitle apply track held across profile preserves the original admitted work | `apply-entry` |
| subtitle apply track held across dispose preserves the original admitted work | `apply-entry` |
| subtitle apply track held across replacement preserves the original admitted work | `apply-entry` |
| subtitle rollback visibility held across reset preserves the original admitted work | `apply-entry` |
| subtitle rollback visibility held across profile preserves the original admitted work | `apply-entry` |
| subtitle rollback visibility held across dispose preserves the original admitted work | `apply-entry` |
| subtitle rollback visibility held across replacement preserves the original admitted work | `apply-entry` |
| subtitle rollback track held across reset preserves the original admitted work | `apply-entry` |
| subtitle rollback track held across profile preserves the original admitted work | `apply-entry` |
| subtitle rollback track held across dispose preserves the original admitted work | `apply-entry` |
| subtitle rollback track held across replacement preserves the original admitted work | `apply-entry` |
| subtitle success turn held across reset preserves the original admitted work | `apply-entry` |
| subtitle success turn held across profile preserves the original admitted work | `apply-entry` |
| subtitle success turn held across dispose preserves the original admitted work | `apply-entry` |
| subtitle success turn held across replacement preserves the original admitted work | `apply-entry` |
| subtitle initialization reaches the stored original apply caller | `apply-entry` |
| subtitle initialization reaches the no preference original apply caller | `apply-entry` |
| subtitle initialization reaches the off original apply caller | `apply-entry` |
| subtitle initialization reaches the language original apply caller | `apply-entry` |
| subtitle initialization reaches the foreign off original apply caller | `apply-entry` |
| subtitle initialization reaches the forced original apply caller | `apply-entry` |
| subtitle live audio policy uses the off apply caller before source priority reselects | `apply-entry` |
| subtitle magic next open uses its diagnostic no-track caller and preserves rollback | `apply-entry` |
| subtitle next channel open uses its diagnostic no-track caller and preserves rollback | `apply-entry` |
| subtitle guide channel open uses its diagnostic no-track caller and preserves rollback | `apply-entry` |
| subtitle Stremio guide open uses its diagnostic no-track caller and preserves rollback | `apply-entry` |
| subtitle automatic language apply rejects its old content after held visibility without setting a second track | `apply-entry` |
| subtitle startup automatic apply superseded by a manual choice returns false to the original restore diagnostic | `apply-entry` |
| subtitle apply non-native success persists the matching identity after its diagnostic turn | `message-entry` |
| subtitle apply native success persists the matching identity after its diagnostic turn | `message-entry` |
| subtitle failed apply falls back to no for previous auto selection | `apply-entry` |
| subtitle failed apply falls back to no for previous 2 selection | `apply-entry` |
| subtitle rollback second native failure preserves one original codec message | `message-entry` |
| subtitle failure replaces the previous snackbar with a floating four-second message | `message-entry` |
| subtitle previous addon identity and external path restore together after an embedded failure | `apply-entry` |
| subtitle previous addon identity and external path clear when native rollback fails | `apply-entry` |
| subtitle empty codec failure uses the generic diagnostic and restores native visibility | `message-entry` |
| subtitle late text failure restores a previously selected bitmap with native visibility enabled | `apply-entry` |
| subtitle failed rollback visibility retries no-track visibility before applying the no track | `message-entry` |
| subtitle saved menu callback after disposal continues a previously null correction through native apply and persistence as-is | `apply-entry` |
| subtitle saved menu callback after disposal throws while clearing the corrected notifier as-is | `apply-entry` |
| subtitle late visibility exception after reset obeys only the original failure admission guard | `apply-entry` |
| subtitle late visibility exception after profile obeys only the original failure admission guard | `apply-entry` |
| subtitle late visibility exception after dispose obeys only the original failure admission guard | `apply-entry` |
| subtitle late visibility exception after replacement obeys only the original failure admission guard | `apply-entry` |
| subtitle late track exception after reset obeys only the original failure admission guard | `apply-entry` |
| subtitle late track exception after profile obeys only the original failure admission guard | `apply-entry` |
| subtitle late track exception after dispose obeys only the original failure admission guard | `apply-entry` |
| subtitle late track exception after replacement obeys only the original failure admission guard | `apply-entry` |
| subtitle manual addon admitted apply continues across content reset before its outer guard rejects persistence | `apply-entry` |
| subtitle rollback waits for successful optimistic persistence across same content | `apply-entry` |
| subtitle rollback waits for successful optimistic persistence across reset | `apply-entry` |
| subtitle rollback waits for successful optimistic persistence across profile | `apply-entry` |
| subtitle rollback waits for successful optimistic persistence across dispose | `apply-entry` |
| subtitle rollback waits for failed optimistic persistence across same content | `apply-entry` |
| subtitle rollback waits for failed optimistic persistence across reset | `apply-entry` |
| subtitle rollback waits for failed optimistic persistence across profile | `apply-entry` |
| subtitle rollback waits for failed optimistic persistence across dispose | `apply-entry` |
| subtitle rollback awaits the newest matching completer when writes finish oldest first | `apply-entry` |
| subtitle rollback awaits the newest matching completer when writes finish newest first | `apply-entry` |
| subtitle delayed preference map is written into the incoming profile as-is | `apply-entry` |
| subtitle admitted rollback clears the active attempt before a later audio preference write | `apply-entry` |
| subtitle old decoder log rolls the current accepted B attempt back as-is | `apply-entry` |
| subtitle delayed A apply exception is rejected after B becomes current | `apply-entry` |
| subtitle admitted A rollback continues over B without a generation recheck | `apply-entry` |
| subtitle repeated decoder corrections reconcile the unified menu and reopened selection | `apply-entry` |
| subtitle checking-turn decoder correction clears optimistic menu while apply remains pending | `apply-entry` |
| subtitle A decoder rollback followed by the same A apply exception is handled once at the unchanged generation | `apply-entry` |
| subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility | `apply-entry` |
| subtitle Android bitmap codec renderer directSurface TV exempt selection preserves rejection and native visibility | `apply-entry` |
| subtitle Android bitmap codec renderer directMediaCodec phone selection preserves rejection and native visibility | `apply-entry` |
| subtitle Android bitmap codec renderer directMediaCodec TV exempt selection preserves rejection and native visibility | `apply-entry` |
| subtitle Android image renderer directSurface phone selection preserves rejection and native visibility | `apply-entry` |
| subtitle Android image renderer directSurface TV exempt selection preserves rejection and native visibility | `apply-entry` |
| subtitle Android image renderer directMediaCodec phone selection preserves rejection and native visibility | `apply-entry` |
| subtitle Android image renderer directMediaCodec TV exempt selection preserves rejection and native visibility | `apply-entry` |
| subtitle track polling times out at exactly fifty polls while ignoring placeholders | `wait-entry` |
| subtitle track polling accepts a real arrival while ignoring placeholders | `wait-entry` |
| subtitle old track poll stops on content token change before touching incoming preferences | `wait-entry` |
| subtitle addon download failure uses the load-failure message caller without native apply or persistence | `message-entry` |
| subtitle addon unexpected diagnostic sink failure reaches its outer failure-message caller | `message-entry` |
| subtitle stored preference rejection preserves its restore-specific diagnostic source | `apply-entry` |


### Step-0 suite baseline and final validation

Fresh full suite at tooling checkpoint `1a51002e7` with S2c application code:
**13,552 successes**, unchanged **13 failures /28 load errors /20 skips**.
`suite_evidence.py compare --against p10/step0/original-suite.jsonl` PASS:
**87 added identities only**, zero missing/changed/fixed/newly skipped identities.
Same Flutter 3.44.8 /Dart 3.12.2 and hooks/no-pub flags; tested tree stayed stable.
`p10/step0/after-step0.jsonl`, environment, stderr and comparison are complete;
this is the new Step-0 baseline for the future move gate, not an allowlist update.

Final unchanged original/current focused runs each pass all 87 cases; files are
byte-identical across worktrees. Final witness runs use the formatted, lint-clean
files and cover every case. New-test analysis has zero issues; format/idempotence,
size/architecture and diff checks pass. Application/pubspecs remain unchanged.
The current S2c analyzer/checker inputs remain selected; production P10 CI/theme
and source-test retargets are reserved for Step 1.

Notes: initial wrong fixture expectations, the matcher that did not pump its
mutated future, and missing direct visibility/request assertions were corrected
on the original before final credit. No production fix or weakened assertion.
The timed-out detached tester left by an uncredited mutation was terminated;
`orphan-cleanup.json` records the exact owned process. No partial/interrupted run
is credited. The public diagnostic-sink failure is an explicit unexpected-error
transport fixture; normal native failures and HTTP 500 are separate cases.

## Phase 10 Step 0b — independent sample and producer equivalences

Claude's independent sample on ORIGINAL `0055d29a7` (identical S2c application
tree) killed **18/20 valid mutations (90%)**. No compile error earns kill credit.
The two survivors are equivalent for the complete original caller/producer
graph; both guards remain in the frozen production move. The original control
and each exact survivor replay run all 87 subtitle-apply cases, unchanged, in
the detached original: completed exit 0, with no skipped or failed behavior.
Commands, patches, test hashes and outcomes: `p10/step0b/replays.json`; exhaustive
tracked-lib producer audit: `producer-audit.json`.

- **n10:** a new apply increments the diagnostic generation before assigning its
  attempt, with no await between them. Both content reset and disposal increment
  that generation immediately before clearing the pointer. The only other
  pointer clear is admitted failure, which sets `handled = true` first, again
  without an await. Renderer replacement has no separate clear. Therefore an
  unhandled attempt with the current generation is still the active attempt;
  removing the pointer disjunct cannot admit another reachable failure.
- **n15:** attempts initialize `persisted` and `successReturned` to false. The
  sole `persisted = true` producer is `_persistTrackChoice`, gated by that same
  attempt's `successReturned`. Its only mutation sets true after the 50 ms
  success turn, and nothing resets it. A write started before that turn can
  physically persist preferences but does not stamp the attempt as persisted.
  Thus `persisted` implies `successReturned`, including held/failed writes.

The existing checking-turn, superseding-apply, reset/disposal/renderer, delayed
exception and optimistic-write cases exercise these windows through real
callers. The systematic Step-0 matrix remains 110 assertion kills, seven
equivalences and 35 invalid candidates; the independent sample adds two
separately audited equivalents, with **18/18 non-equivalent candidates killed**.
No additional behavior case or production change is needed.

| Independent point | Final classification | Witness / proof |
|---|---|---|
| `n1` | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders; subtitle track polling accepts a real arrival while ignoring placeholders; subtitle old track poll stops on content token change before touching incoming preferences |
| `n2` | assertion-killed | subtitle track polling times out at exactly fifty polls while ignoring placeholders; subtitle track polling accepts a real arrival while ignoring placeholders; subtitle old track poll stops on content token change before touching incoming preferences |
| `n3` | assertion-killed | PiP iOS entry prepares native subtitles once, sends its distinct handle and leaves auto-enter unarmed; PiP iOS held handle across owner preserves original entry and finalization boundaries; PiP iOS held handle across profile preserves original entry and finalization boundaries; PiP iOS held subtitle across dispose preserves original entry and finalization boundaries |
| `n4` | assertion-killed | subtitle Android bitmap codec renderer directSurface TV exempt selection preserves rejection and native visibility; subtitle Android bitmap codec renderer directMediaCodec TV exempt selection preserves rejection and native visibility; subtitle Android image renderer directSurface TV exempt selection preserves rejection and native visibility; subtitle Android image renderer directMediaCodec TV exempt selection preserves rejection and native visibility |
| `n5` | assertion-killed | subtitle Android bitmap codec renderer directSurface phone selection preserves rejection and native visibility; subtitle Android bitmap codec renderer directMediaCodec phone selection preserves rejection and native visibility; subtitle Android image renderer directSurface phone selection preserves rejection and native visibility; subtitle Android image renderer directMediaCodec phone selection preserves rejection and native visibility |
| `n6` | assertion-killed | subtitle initialization reaches the stored original apply caller; subtitle apply non-native success persists the matching identity after its diagnostic turn; subtitle late visibility exception after profile obeys only the original failure admission guard; subtitle saved menu callback after disposal throws while clearing the corrected notifier as-is |
| `n7` | assertion-killed | subtitle automatic language apply rejects its old content after held visibility without setting a second track; subtitle startup automatic apply superseded by a manual choice returns false to the original restore diagnostic |
| `n8` | assertion-killed | subtitle apply visibility held across reset preserves the original admitted work; subtitle apply non-native success persists the matching identity after its diagnostic turn; subtitle apply native success persists the matching identity after its diagnostic turn; subtitle apply visibility held across profile preserves the original admitted work |
| `n9` | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn; subtitle apply native success persists the matching identity after its diagnostic turn; subtitle rollback waits for successful optimistic persistence across same content; subtitle old decoder log rolls the current accepted B attempt back as-is |
| `n10` | equivalent | Current generation plus unhandled implies active; exhaustive pointer/generation producers above. |
| `n11` | assertion-killed | subtitle initialization reaches the stored original apply caller; subtitle failed apply falls back to no for previous auto selection; subtitle initialization reaches the no preference original apply caller; subtitle initialization reaches the language original apply caller |
| `n12` | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `n13` | assertion-killed | subtitle previous addon identity and external path clear when native rollback fails |
| `n14` | assertion-killed | subtitle previous addon identity and external path restore together after an embedded failure; late embedded failure restores previous addon selection once |
| `n15` | equivalent | persisted implies successReturned; sole producer and monotonic flag above. |
| `n16` | assertion-killed | off attempt ignores unrelated audio preference identity; external attempt ignores unrelated audio preference identity; subtitle admitted rollback clears the active attempt before a later audio preference write; embedded attempt ignores unrelated audio preference identity |
| `n17` | assertion-killed | subtitle repeated decoder corrections reconcile the unified menu and reopened selection; subtitle checking-turn decoder correction clears optimistic menu while apply remains pending |
| `n18` | assertion-killed | subtitle apply non-native success persists the matching identity after its diagnostic turn; subtitle apply native success persists the matching identity after its diagnostic turn; subtitle repeated decoder corrections reconcile the unified menu and reopened selection; subtitle empty codec failure uses the generic diagnostic and restores native visibility |
| `n19` | assertion-killed | subtitle failure replaces the previous snackbar with a floating four-second message |
| `n20` | assertion-killed | subtitle failure replaces the previous snackbar with a floating four-second message |

The Step-0b baseline is the completed `p10/step0/after-step0.jsonl`: **13,552
successes /13 failures /28 load errors /20 skips**, with the 87 additions versus
the original and no changed/missing identity. Application, tests, dependencies
and SDK are unchanged by this documentation-only addendum; baseline reuse is
recorded in `p10/step0b/baseline-note.json`. No allowlist change.
