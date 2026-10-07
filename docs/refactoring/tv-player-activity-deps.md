# Android TV player activity — dependency map

Read-only survey at `39c630303` (six parts, A–F). Line numbers refer to that revision of `android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt`.

---

## AndroidTvTorrentPlayerActivity.kt — responsibility map, chunk A (lines 136–3000)

File: android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt
Note: the chunk boundary at 3000 falls INSIDE `setupPlayer()` (2736–3134). Its tail
(3001–3134: LoadControl presets, player build, listener attach, subtitle listener,
SubtitleSettings wiring, IPTV network callback) is included in this map because it
cannot be separated from the head. "Subtitle language prefs" in this chunk exist only
as the DefaultTrackSelector parameters in setupPlayer (2737–2806); the rest of the
subtitle subsystem only has FIELD declarations here (1194–1340).

Shape of the chunk: ~65% field declarations for clusters whose logic lives elsewhere
(lines 136–1377 interleave fields with ~5 small logic clusters), then
`playbackListener` (1499–2007), `onCreate` (2014–2186), metadata receiver
(2188–2484), `bindViews` (2486–2676), origin helpers (2678–2701), codec selector
(2715–2734), `setupPlayer` (2736–3134).

---------------------------------------------------------------------------------
## 1. Responsibility clusters

### C1 View references (fields only)
Lines 138–259 (+ 993–1007 IPTV guide views, 1057–1066 EPG views, 1091–1092 Stremio
badge, 1179–1188 Stremio TV guide views, 1195 subtitleSettingsRoot, 1296 statusPill,
1302–1304 autoSync pill, 1374–1376 buffering/PikPak indicators).
- lateinit (bound in bindViews 2486): playerView@139, startupGateView@140,
  startupGateStatus@141, titleContainer@142, titleView@143, titleOttContainer@145,
  ottEpisodeBadge@146, ottEpisodeTitle@147, ottRatingContainer@148, ottRating@149,
  channelBadge@150, subtitleOverlay@151, subtitleControlsLift@152, playlistOverlay@153,
  playlistView@154, seasonTabsContainer@155, nextOverlay@156, nextText@157,
  nextSubtext@158, nextBackdrop@161, upNextCard@164, upNextPoster@165, upNextTitle@166,
  upNextCountdown@167, skipSegmentButton@168, seekbar*@177–182, bufferingIndicator@1374,
  pikPakReactivationIndicator@1375, pikPakReactivationText@1376,
  seekFeedbackManager@815 (built in onCreate 2176).
- nullable controls (bound in setupControls@4255, outside chunk): controlsOverlay@187,
  pauseButton@188, iptv*Button@189–195, audio/subtitle/aspect/speed/nightModeButton
  @201–205, debrifyTime*@208–212, cinemaProgress*@215–218, ott*@224–250.
- Mixed state living among views: upNextVisible@169, upNextTargetIndex@170,
  upNextDismissedForIndex@171, upNextHandler@172, seasonTabs@173, movieTabs@174,
  seekbarBackgroundWidth@183, currentSeekSpeed@184, iptvUpPressActive@198,
  iptvUpLongPressHandled@199, originalControlDockOrder@200, dockTagsCacheKey@242,
  dockTagsCache@243, ottShowName@254 (@Volatile), cinemaProgressTrackWidth@255,
  cinemaSeekMode@256, cinemaSeekWasPlaying@257, cinemaProgressAnimator@258,
  cinemaLastAnimatedProgress@259.
- Lazy owned object: iptvRecordingController@197 (`by lazy { IptvRecordingController(this) }`).

### C2 Player core / decoder diagnostics
Lines 261–340.
- Fields: player@262, nativeAudioRouting@263, trackSelector@264, subtitleListener@265,
  displayMatchMode@266, displayModeController@267, offsetRenderersFactory@340.
- decoderAnalyticsListener@269–316 (anon AnalyticsListener; private inputFormat@270):
  onAudioTrackInitialized@272, onVideoInputFormatChanged@282, onVideoDecoderInitialized@291.
- androidDecoderStatus@318 (pure-ish: string rules + MediaCodecList query).
- Reads: nightModeIndex@842 (C9), displayModeController, player.
- Calls (outside chunk): initializeLoudnessEnhancer@16529, syncAudioEffectSession@16519.

### C3 IPTV live recovery + twin trial
Lines 342–807 logic, 852–1054 state (interleaved). Members:
iptvLiveRecovery@369 (lazy, IptvLiveRecovery.Callbacks anon impl 372–402),
iptvLiveRecoveryEligible@410, performIptvLiveRetune@424, beginIptvTwinTrial@494,
judgeIptvTwinTrial@517, acceptIptvTwinTrial@544, failIptvTwinTrial@558,
onIptvTwinTrialTimeout@581, scheduleIptvTwinTrialTimeout@589,
rearmIptvTwinTrialDeadline@603, parkIptvTwinTrialRestore@618,
restoreParkedIptvTwinIfNeeded@630, clearParkedIptvTwinRestore@641,
clearIptvTwinTrial@650, restoreAcceptedIptvTwinAfterAuth@663, classifyIptvError@685,
inner class IptvLiveLoadErrorPolicy@709–749 (liveNow@710, getRetryDelayMsFor@713,
getMinimumLoadableRetryCount@747), showIptvReconnectPill@751, hideIptvReconnectPill@777,
dpToPx@781, iptvDiagAnalyticsListener@784–807 (onRenderedFirstFrame@785,
onLoadCompleted@800).
- Owned fields: iptvTuneDiagnostics@344, iptvLiveRetuneInFlight@354,
  iptvStoppedAtRealtime@359, IPTV_LIVE_REJOIN_AFTER_MS@361, iptvNetworkCallback@363,
  iptvReconnectPill@367, iptvHlsForcedUrls@888, iptvStrictTsUrls@897,
  iptvStrictTsActive@901 (@Volatile), iptvStartsWithStrictTs@906 (lazy),
  iptvTwinTrialOriginalUrl@928, iptvTwinTrialUrl@936, iptvTwinFailedUrls@939,
  iptvTwinPreferredUrls@944, iptvTwinTrialTimeout@946, iptvTwinTrialHandler@947,
  iptvTwinTrialRestoreOriginal@955, iptvTwinTrialRestoreTwin@959,
  iptvTwinTrialLastFrames@964, iptvTwinTrialAdvanceSince@965,
  iptvTwinTrialStartedRealtime@966, IPTV_TWIN_TRIAL_STABLE_MS@972,
  IPTV_TWIN_TRIAL_TIMEOUT_MS@979, IPTV_TWIN_TRIAL_POST_READY_MS@986,
  IPTV_TWIN_TRIAL_MAX_MS@990.
- Reads other clusters: isIptvMode@862, iptvChannels@863, currentIptvIndex@864,
  currentIptvStreamUrl@992, iptvStremioChannelKey@1079, iptvStremioWinnerReported@1082,
  sleepStopLatched@1282, sleepTimerMode@1269, player, playerView, isFinishing/isDestroyed.
- Writes other clusters: iptvStartOverActive@865, iptvStartOverLoading@866,
  iptvStartOverTimelineVisible@867, iptvCatchupToken@868 (performIptvLiveRetune 429–434);
  manualSourceRestoreInProgress@1142 (iptvDiagAnalyticsListener 793).
- iptvDiagAnalyticsListener is actually MIXED: also drives VOD startup/manual-source
  commit (mediaServerPlaybackLog, restartProgressUpdates, commitManualSourceCandidate,
  commitStartupCandidate) — belongs to C11 as much as C3.
- Out-of-chunk users: hideIptvReconnectPill@14342/19153, restoreParkedIptvTwinIfNeeded
  @7421/19105, clearParkedIptvTwinRestore@14315, parkIptvTwinTrialRestore@19151,
  clearIptvTwinTrial@14307/19151/19305, iptvLiveRecovery.*@3112/3116/3125/7431/7434/
  14340–14341/19113/19152/19306; setIptvMediaItem@14284 reads iptvStrictTsUrls,
  iptvStartsWithStrictTs, iptvTwinPreferredUrls, iptvHlsForcedUrls, iptvLiveRetuneInFlight.

### C4 Playback session / resume state
Lines 818–859, 1378–1449.
- Fields: payload@818, currentIndex@819, activeVodHeaders@820 (@Volatile),
  protectedStreamClient@821, mediaPreparationScope@822, mediaPreparationGeneration@823,
  pendingSeekMs@824, percentSeekApplied@825, pendingItemTraktPercent@830,
  isAutoAdvancing@834, controlsMenuVisible@835, playlistVisible@836, seekbarVisible@837,
  seekbarPosition@838, videoDuration@839, playlistMode@850, playlistAdapter@851,
  seriesPlaylistAdapter@852, moviePlaylistAdapter@853, movieGroups@854,
  continuousShuffleEnabled@855, shuffleBag@856, showShuffle@857,
  showShuffleGeneration@858, lastBackPressTime@859, hasEverBeenReady@1377,
  resumeHoldTargetMs@1388, resumeHoldArmedAtMs@1389, maxStableDurationMs@1438,
  lastRealPositionMs@1439, locallyCompletedItemKeys@1446, recoveryCompletedItemKeys@1447.
- Resume-hold functions: armResumeHold@1391, releaseResumeHold@1408,
  heldResumePositionMs@1416 (constants RESUME_HOLD_TOLERANCE_MS/SETTLE_MS @20135–20136).
  Out-of-chunk callers: armResumeHold@19899; releaseResumeHold@4632/7907/8031/8123/
  8324/19900; heldResumePositionMs@16832/17249/18440/18776.

### C5 IPTV mode / guide / zap / EPG / Stremio-IPTV state (fields only)
Lines 861–883, 992–1087. isIptvMode@862 … iptvStremioStallRunnable@1086,
iptvSeriesAudioKey@875, iptvPreferredAudioLang@876, currentIptvHttpHeaders@883
(@Volatile, read on loader threads by setupPlayer resolver 2892), iptvBrowseHandler@1022,
iptvZapPendingInputs@1033. No logic in chunk.

### C6 Stremio sources / startup failover / manual source switch (fields only)
Lines 1088–1175. stremioSources@1089, currentStremioSourceIndex@1090,
startupFailoverCursor@1100 … manualSourceRestoreInProgress@1142, networkPatience@1147,
networkBuffer@1148, iptvDecoderMode@1152, seriesSourceTabs@1158 … moreSourcesLoadingMode
@1165, data class TvSourceAddon@1171, sourceAddons@1172, addonFetchState@1173,
addonPackProbing@1174, recovery*@1120–1128, sourcePersistenceSessionId@1119.

### C7 Stremio TV guide (fields only) Lines 1176–1192.

### C8 Subtitles (fields only) Lines 1194–1238, 1284–1340.
subtitlePanel@1197, syncOverlay@1198, linePickerOverlay@1199, unifiedMenu@1200,
sourceBrowser@1201, subtitleSeekHandler@1202 + subtitleSeekRunnable@1203 (logic:
`player.seekTo(currentPosition)`), stremio subtitle state 1209–1237,
subtitleScope@1238 (CoroutineScope Main+SupervisorJob), external subtitle renderer
1289–1297 (externalSubtitleHandler@1293, statusPillHideRunnable@1297), auto-sync
1302–1339 (autoSyncPillAnnounceDismissRunnable@1310, autoSyncCardHideRunnable@1316,
ladder 1327–1330, verify 1337–1339), speechTap@811, autoSyncRunning@812.

### C9 Skip segments / sleep timer / display presets / focus (fields only)
Skip: SkipSegmentRequest@1243, skipSegmentScope@1251, skipSegmentFetchJob@1252 …
skipSegmentCache@1259. Sleep: SleepTimerMode enum@1268, sleepTimerMode@1269,
sleepTimerDeadlineElapsedMs@1270, sleepTimerHandler@1271, sleepTimerRunnable@1272,
sleepTimerMinuteOptions@1273, sleepStopLatched@1282. Presets: resizeModeIndex@840,
playbackSpeedIndex@841, nightModeIndex@842, loudnessEnhancer@843,
systemAudioEffectsEnabled@847, skipSegmentsEnabled@848, skipSegmentProviderId@849,
resizeModes@1347, resizeModeLabels@1354, playbackSpeeds@1356, playbackSpeedLabels@1357,
nightModeGains@1359, nightModeLabels@1360. Focus: isNavigating@1342,
navigationTargetPosition@1343, focusRecoveryHandler@1344, focusRecoveryRunnable@1345.
PikPak retry: isPikPakRetrying@1368, pikPakRetryCount@1369, pikPakRetryId@1370,
pikPakRetryHandler@1371. Buffering debounce: bufferingHandler@1448,
bufferingDebounceRunnable@1449.

### C10 Periodic tickers
Lines 1362–1365 handlers (progressHandler, controlsHandler, seekbarHandler), 1451–1497.
- progressRunnable@1451: sendProgress(false), maybeShowUpNext(), iptvTuneDiagnostics
  .onProgress, IPTV: iptvLiveRecovery.onProgress/onVideoFrames, judgeIptvTwinTrial(frames);
  re-posts every PROGRESS_INTERVAL_MS (5000, @20144).
- hideControlsRunnable@1484: isFocusInControlsOverlay / hideControlsMenu /
  scheduleHideControlsMenu.
- seekbarProgressRunnable@1492: updateSeekbarProgress, re-post 100 ms on seekbarHandler.

### C11 Player event dispatch — `playbackListener` (1499–2007)
onEvents@1500, onPlaybackStateChanged@1512 (READY 1515–1641, BUFFERING 1642–1647,
ENDED 1648–1795), onIsPlayingChanged@1800, onPlayerError@1812, onPositionDiscontinuity
@1952, onMediaItemTransition@1976, onAudioSessionIdChanged@1998.
This is a router touching nearly every cluster:
- READY: pendingShufflePlayback (field @5403) clear, hasEverBeenReady, C3
  (iptvLiveRecovery.onReady, rearmIptvTwinTrialDeadline), reportIptvStremioWinnerIfNeeded,
  hideBufferingIndicator, startup commit for torrent rows (startupFailoverCursor,
  stremioSources, currentPlaybackItemIsPikPak, commitStartupCandidate), RESUME SEEK
  POLICY 1545–1630 (reads payload.startAtPercent/traktProgressPercent, writes
  percentSeekApplied/pendingSeekMs/pendingItemTraktPercent, armResumeHold, seekTo),
  night mode init, syncAudioEffectSession.
- ENDED: Stremio-TV pre-commit guard → failStartupCandidate; manual switch guard →
  failManualSourceCandidate; live EOF → sleep END_OF_ITEM stop or iptvLiveRecovery.onEnded;
  spurious-end guard (maxStableDurationMs/lastRealPositionMs 1699–1708);
  recordPlaybackLifecycle + sendProgress(true); sleep stop; IPTV next episode;
  shuffle (playShowShuffle, pickShuffleIndex, showNextOverlay + 1500 ms postDelayed
  playItem); getNextPlayableIndex; Stremio TV requestStremioTvNext; series
  requestEpisodeFetch / requestAdjacentEpisodeFetch / requestQuickPlayNextEpisode; finish().
- onPlayerError: priority ladder (order is load-bearing, see comments 1862–1930):
  shuffle → manual restore → manual switch (PikPak defer) → startup cursor (PikPak defer)
  → iptvTuneDiagnostics.onError → start-over (retryIptvAsHlsIfUnrecognized,
  cancelPendingIptvCatchupRequest, beginIptvPlayback) → twin-trial owns error →
  restoreAcceptedIptvTwinAfterAuth → HLS-force retry → BEHIND_LIVE_WINDOW rejoin →
  tryNextIptvStremioCandidate → iptvLiveRecovery.onFatalError(classifyIptvError) →
  log + reportDecoderFailure.
- onPositionDiscontinuity: speechTap.notifyDiscontinuity; backward seek >3 s → releaseResumeHold.
- onMediaItemTransition: speechTap.reset; releaseLoudnessEnhancer unless REPEAT.
- onAudioSessionIdChanged: syncAudioEffectSession; re-init LoudnessEnhancer.

### C12 Launch / onCreate (2014–2186)
Order: DiagnosticFileLog.initialize → sourcePersistenceSessionId from intent →
recordCritical(activity_create) → super.onCreate → NativePlayerPreferences.fromIntent
(failure: Toast + finish + return, 2025–2032) → setContentView → FLAG_KEEP_SCREEN_ON →
RecordingRegistry.addListener(recordingRegistryListener@9254) → loadPlayerDefaults@16560
→ payload file read+delete (2044–2069, fallback PAYLOAD_KEY extra) → missing → finish →
JSON pre-scan (continuousShuffleEnabled, sourcePersistenceSessionId, recovery*,
useAddonTextFormatting, showSourceAddonLogos) → mode=="iptv" → initIptvMode@8802 and
RETURN (IPTV skips everything below) → parsePayload@18912 → empty → finish →
currentIndex → custom font (SubtitleFontManager) → bindViews → setupPlayer →
setupSeekbar@3135 → setupPlaylist@3523 → setupControls@4255 → setupStremioSources@17814
→ stremioTvGuide → initStremioTvGuide@19445 + updateCatalogEpisodeControls →
initialSubtitles → injectedSubtitles → SeekFeedbackManager → setupBackPressHandler@19161
→ setupMetadataReceiver → StremioSubtitleService(this) → beginStartupFailoverIfEligible
@17180 → playItem(currentIndex)@4556.
- Owns field playerPreferences@2012 (lateinit). rawPayload is re-parsed as JSONObject 4×
  (2082, 2126, 2148, 2161).

### C13 Episode-metadata receiver (2009–2010, 2188–2484)
setupMetadataReceiver@2188, readStagedExtra@2229, handleMetadataUpdate@2250,
requestMetadataFromFlutter@2454. Owns metadataUpdateReceiver@2010.
- Reads/writes: ottShowName (C1), ottSkinInstalled, payload.imdbId (mutates model),
  payload.guideEpisodes (clear/addAll), payload.items[i] (copy replace), currentIndex,
  player.currentPosition/duration, seriesPlaylistAdapter, moviePlaylistAdapter.
- Calls: updateOttIdentity@5641, fetchStremioSubtitles@4940, rebuildPlaylistContent@3600,
  updateCatalogEpisodeControls@5317, updateTitle@5597, mergeLateMetadataResumePosition
  @20365 / mergeLateMetadataDuration (top-level internal funs).
- Threading: receiver runs on main; handleMetadataUpdate wraps UI in runOnUiThread
  (2263, 2321, 2430) — redundant but present; payload mutation happens on main.
- requestMetadataFromFlutter called again out-of-chunk @18666.

### C14 View binding + sub-controller construction — bindViews (2486–2676)
findViewById for C1; startup_back/startup_details click listeners (AlertDialog 2492);
SubtitleControlsLiftController(subtitleOverlay, dp(24)); installGuideOverlaySkin@3200
BEFORE playlist bind, bindGuideSkinViews@3210 after; skipSegmentButton→skipActiveSegment
@8307; SubtitlePanelController(callbacks = subtitlePanelCallbacks@15784);
UnifiedMenuController(callbacks = unifiedMenuCallbacks@14828, sectionIds =
unifiedSectionIds@14806); TvSourceBrowserController with an INLINE anon Callbacks
(2577–2665) reading stremioSources, payload, currentIndex, currentStremioSourceIndex,
useAddonTextFormatting, showSourceAddonLogos, seriesSourceTabs, seriesPacksFetched,
seriesEpisodesFetched, movieMoreSources, movieSourcesFetched, moreSourcesLoadingMode,
sourceAddons, addonFetchState, addonPackProbing; calls sourceVisibleForEpisode
(TvSourceBrowserController.kt:14), requestMoreTorrentSources@18181,
requestAddonTorrentSources@18272, sourceSelectionLog@17804, onStremioSourceSelected@17944.

### C15 Media-pipeline construction — setupPlayer (2736–3134) + helpers
buildProtectedMediaOrigins@2678 (callers 4568/4620/4773), originKey@2690 (also 18782),
iptvMediaCodecSelector@2715 (reads isIptvMode, iptvDecoderMode at codec-query time).
setupPlayer steps: DefaultTrackSelector + language/text params (2737–2806; prefs keys
player_default_audio_language, player_default_subtitle_language,
subtitle_only_foreign_audio, subtitle_forced_only; pt-BR special case 2803;
IPTV setAllowVideoNonSeamlessAdaptiveness(false) 2757) → SpeechFeatureTap → speechTap
→ nativeAudioRouting.update → NativeAudioRenderersFactory (EXTENSION_RENDERER_MODE_PREFER,
decoder fallback, codec selector) → OffsetRenderersFactory → DefaultHttpDataSource
(timeouts from networkPatience, VOD only; Chrome UA in default props) →
protectedStreamClient → VodHttpDataSource.Factory → DefaultDataSource → Resolving
(activeVodHeaders by origin) → IPTV Resolving (currentIptvHttpHeaders) → IPTV
RecordingDataSource (sets iptvRecordingController.onAborted) → MediaSourceFactory (IPTV:
aggressive/strict TS extractors switched per-call on iptvStrictTsActive +
IptvLiveLoadErrorPolicy) → ExoPlayer.Builder (handle noisy, WAKE_MODE_NETWORK,
displayMatchMode frame-rate strategy) → LoadControl: YouTube-merge preset 2998–3012, else
VOD networkBuffer preset with heap budget 3013–3056 → build, setPlaybackSpeed, add
playbackListener + 2 analytics listeners, playerView.player → subtitleListener (onCues
→ subtitleOverlay unless externalSubtitleActive) → SubtitleSettings sync/resetSyncOffset/
setActiveSubtitleIdentityProvider(currentSubtitleIdentity) → applySubtitleSettings →
applyResizeMode → requestFocus → IPTV: setKeepContentOnPlayerReset(true) +
registerDefaultNetworkCallback → iptvLiveRecovery.setOffline.

---------------------------------------------------------------------------------
## 2. External effects per cluster

| Cluster | Effects |
|---|---|
| C2 | Media3 AnalyticsListener; MediaCodecList query (API≥29); DiagnosticFileLog.record("decoder_initialized"); Log.i(DECODER_LOG_TAG); LoudnessEnhancer/AudioEffectSession via helpers. |
| C3 | Handler(main) inside IptvLiveRecovery@371; iptvTwinTrialHandler.postDelayed (589–594); setIptvMediaItem (ExoPlayer re-prepare) @483/504/571/637/676; playerView.setKeepContentOnPlayerReset; addContentView reconnect pill (770); IptvRecordingController finalize; Media3 LoadErrorHandlingPolicy (runs on loader thread, reads iptvChannels/currentIptvIndex unsynchronised 711). |
| C4 | mediaPreparationScope (coroutines, cancelled onDestroy); SystemClock for resume hold. |
| C8 | subtitleScope coroutines; subtitleSeekHandler; externalSubtitleHandler (status pill + auto-sync runnables). |
| C9 | sleepTimerHandler; skipSegmentScope coroutine; pikPakRetryHandler; bufferingHandler; focusRecoveryHandler. |
| C10 | progressHandler.postDelayed 5 s; seekbarHandler 100 ms; controlsHandler. sendProgress → MethodChannel (outside chunk). |
| C11 | ExoPlayer seekTo/seekToDefaultPosition/prepare/play; Toasts (1684, 1719); progressHandler.postDelayed 1500 ms auto-advance (1743, 1755); finish(); DiagnosticFileLog("player_error"); window keep-screen via holdScreenForPlayback/releaseScreenForSleep. |
| C12 | DiagnosticFileLog init/recordCritical/record/recordError; file read + delete of payloadPath; window FLAG_KEEP_SCREEN_ON; RecordingRegistry.addListener; SharedPreferences via loadPlayerDefaults/NativePlayerPreferences; SubtitleFontManager.applyCustomFontIfValid; Toast + finish on rejected prefs. |
| C13 | registerReceiver("com.debrify.app.tv.UPDATE_EPISODE_METADATA", RECEIVER_NOT_EXPORTED on API≥33); file read of staged cacheDir JSON (prefix-validated, read-only — no delete by design 2222–2225); MethodChannel `requestEpisodeMetadata` via MainActivity.getAndroidTvPlayerChannel() posted to main (2473–2475). |
| C14 | findViewById; AlertDialog; MethodChannel `requestStreamBadges` {sourcePersistenceSessionId, name, description} (2607); focus: playerView requestFocus on browser hide (2663). |
| C15 | SharedPreferences reads via playerPreferences (4 keys); ExoPlayer/Media3 construction; OkHttp-backed ProtectedStreamHttp client; ActivityManager.largeMemoryClass; ConnectivityManager.registerDefaultNetworkCallback; SubtitleSettings / SubtitleFontManager singletons (identity provider captures `this`). |

---------------------------------------------------------------------------------
## 3. Coupling (outgoing calls outside chunk)

- C2 → initializeLoudnessEnhancer@16529, syncAudioEffectSession@16519.
- C3 → setIptvMediaItem@14284, isCurrentIptvSegmented@9274, xtreamTsTwin@9286,
  finalizeIptvRecordingIfActive@9654, updateRecordButtonState@9357,
  updateIptvControlPresentation@9678, mediaServerPlaybackLog@17795,
  restartProgressUpdates@16651, commitManualSourceCandidate@17301,
  commitStartupCandidate@17497. Callers into C3: C11, C10, onStart@19083, onStop@19122,
  onDestroy@19270, setIptvMediaItem, play button @7421/7431.
- C10 → sendProgress@16801, maybeShowUpNext@8691, judgeIptvTwinTrial (C3),
  isFocusInControlsOverlay@7381, hideControlsMenu@7535, scheduleHideControlsMenu@7614,
  updateSeekbarProgress@7662.
- C11 → sendPlaybackMaintenanceState@16927, tryAutoSelectAddonSubtitle@6915,
  reportIptvStremioWinnerIfNeeded@14684, hideBufferingIndicator@19260,
  showBufferingIndicatorDebounced@19247, currentPlaybackItemIsPikPak@17702,
  commitStartupCandidate, failStartupCandidate@17566, failManualSourceCandidate@17367,
  recordPlaybackLifecycle@16664, sendProgress, cancelSleepTimer@8367,
  releaseScreenForSleep@8395, holdScreenForPlayback@8401, noteLiveChannelPlaying@12429,
  nextIptvEpisode@14201, switchToIptvChannel@12340, playShowShuffle@5469,
  pickShuffleIndex@5574, failShufflePlayback@5421, showNextOverlay@8650,
  hideNextOverlay@8663, playItem@4556, getNextPlayableIndex@8484,
  requestStremioTvNext@19947, guideAdjacent@16971, requestEpisodeFetch@16993,
  requestAdjacentEpisodeFetch@17064, requestQuickPlayNextEpisode@17150,
  updatePauseButtonLabel@7626, showStatusPillTransient@16176, startupLog@17784,
  schedulePikPakGateReprepare@17715, retryIptvAsHlsIfUnrecognized@14431,
  cancelPendingIptvCatchupRequest@11394, beginIptvPlayback@14479,
  tryNextIptvStremioCandidate@14613, reportDecoderFailure@14411,
  initializeLoudnessEnhancer, releaseLoudnessEnhancer@16547, syncAudioEffectSession.
- C12 → loadPlayerDefaults, initIptvMode, parsePayload, diagnosticProvider@17775,
  bindViews/setupPlayer (in chunk), setupSeekbar, setupPlaylist, setupControls,
  setupStremioSources, initStremioTvGuide, updateCatalogEpisodeControls,
  setupBackPressHandler, beginStartupFailoverIfEligible, playItem, startupLog.
- C13 → updateOttIdentity, fetchStremioSubtitles, rebuildPlaylistContent,
  updateCatalogEpisodeControls, updateTitle, mergeLateMetadata*@20365.
- C14 → installGuideOverlaySkin, bindGuideSkinViews, skipActiveSegment, dp@6644,
  requestMoreTorrentSources, requestAddonTorrentSources, sourceSelectionLog,
  onStremioSourceSelected; consumes subtitlePanelCallbacks@15784,
  unifiedMenuCallbacks@14828, unifiedSectionIds@14806.
- C15 → applySubtitleSettings, applyResizeMode, currentSubtitleIdentity,
  updateRecordButtonState; IptvLiveLoadErrorPolicy + iptvLiveRecovery (C3).
- Note duplicate helpers: dpToPx@781 (C3) vs dp@6644 used by bindViews.

---------------------------------------------------------------------------------
## 4. Extraction candidates (low → high risk)

1. **Pure functions → top-level/internal object** (lowest). androidDecoderStatus@318,
   classifyIptvError@685 (only needs PlaybackException), originKey@2690,
   buildProtectedMediaOrigins@2678, readStagedExtra@2229 (needs cacheDir: pass File),
   resume-seek target computation 1574–1603 (pure given duration/pos/launchTrakt/
   pendingItemTraktPercent/pendingSeekMs). No host interface. Enables plain JVM tests.
2. **ResumeHold** (1388–1430): two Longs + 3 fns, injectable clock. Host: none
   (callers just call methods). Constants already in companion. 11 out-of-chunk call
   sites to repoint.
3. **TrackSelectorParameters builder** (2737–2806): pure function of
   (prefs getString/getBoolean, isIptvMode) → Parameters. Robolectric already asserts
   TEXT disabled under forcedOnly (NativePlayerSettingsConsumptionTest) — reflection reads
   field `trackSelector`, so keep that field on the activity.
4. **EpisodeMetadataReceiver** (C13): owns receiver registration/unregistration and
   staged-file reading. Host/Callbacks needs: `payload()`, `currentIndex()`,
   `livePositionMs()/liveDurationMs()`, `onShowName(String)`, `onImdbDiscovered(item)`,
   `onGuideAdopted()`, `onItemsUpdated()`, `methodChannel()` provider. Must keep
   register-then-request ordering (2207–2216) and unregister in onDestroy (~19365).
5. **IptvMediaPipelineFactory** (C15 data-source/extractor/load-error part 2828–2964):
   needs suppliers for `activeVodHeaders`, `currentIptvHttpHeaders`, `iptvStrictTsActive`
   (all read on loader threads — must stay @Volatile reads via lambdas), plus
   `liveNow()` for IptvLiveLoadErrorPolicy (currently non-volatile cross-thread read of
   iptvChannels/currentIptvIndex — preserve as-is, don't "fix" incidentally),
   iptvRecordingController, networkPatience. Medium risk: invariant comments
   (UA in default props, "standard" = stock) must survive; no tests cover it.
6. **IptvTwinTrialController** (C3 twin part 489–681 + fields 914–990): own handler +
   state. Callbacks: `currentStreamUrl()`, `currentLiveEntry()`, `retune(entry, url)`
   (wrapping iptvLiveRetuneInFlight + setIptvMediaItem), `wantsPlayback()`,
   `sleepLatched()`, `isTornDown()`, `diagnostics`. setIptvMediaItem@14284 reads
   iptvTwinPreferredUrls/clearParkedIptvTwinRestore/clearIptvTwinTrial; onStop/onStart
   use park/restore. Medium-high: subtle ordering, session-memory sets shared with
   strict-TS (iptvStrictTsUrls, iptvHlsForcedUrls), zero tests.
7. **IptvLiveRecoveryHost** (performIptvLiveRetune, eligibility, reconnect pill): the
   IptvLiveRecovery class already exists; moving the anon Callbacks + retune policy out
   requires access to start-over state, recording controller, sleep state, Stremio-IPTV
   ladder state. High coupling — do after C5 IPTV state has a home.
8. **PlaybackEventRouter** (C11, playbackListener) — HIGHEST. It is a priority-ordered
   dispatcher over ~45 activity functions across 8 clusters; onPlayerError ordering and
   STATE_ENDED live/sleep/spurious guards are behaviour contracts. Extract last, after
   the clusters it calls have narrow interfaces; consider splitting READY resume policy
   (candidate 1) and ENDED advance policy first. Tests reflect on field
   `playbackListener` (StremioTvStartupWatchdogTest) — keep the name or update tests.
- onCreate (C12) should stay as composition root; extraction = shrinking it by moving
  the JSON pre-scan + font/guide/subtitle parsing into a launch-parser (parse once,
  not 4×) — behaviour-preserving only if each try/catch scope is preserved (a failure
  in one block currently doesn't abort the others).
- bindViews (C14): extract the inline TvSourceBrowserController.Callbacks (2577–2665)
  into a named object/val like subtitlePanelCallbacks — low risk, pure move.

---------------------------------------------------------------------------------
## 5. Lifecycle / teardown facts (as implemented)

- onCreate early exits (prefs rejected 2030, payload missing 2076, invalid 2112) happen
  BEFORE bindViews, so onDestroy@19270 must tolerate unbound lateinit views — it guards
  with `::x.isInitialized` (subtitleControlsLift, startupGateView, seekFeedbackManager,
  pikPakReactivationIndicator, bufferingIndicator, playlistView, seekbarOverlay).
  Covered by NativePlayerRejectedLaunchTest. Any extracted collaborator must be
  nullable/lazy-safe in teardown for the same reason. Note RecordingRegistry.addListener
  (2038) runs only after the prefs check, but removeListener always runs in onDestroy.
- IPTV launch returns at 2099 → no setupMetadataReceiver, no stremioSubtitleService,
  no SeekFeedbackManager from this path (initIptvMode does its own setup).
- onStop@19122 order: cancelPendingIptvCatchupRequest → recordPlaybackLifecycle →
  sendPlaybackActivityState(false) → final sendProgress snapshot → super.onStop →
  finalizeIptvRecordingIfActive → `if (!parkIptvTwinTrialRestore()) clearIptvTwinTrial()`
  → iptvLiveRecovery.cancel() → hideIptvReconnectPill → iptvStoppedAtRealtime = now →
  player.pause → remove externalSubtitleTicker.
- onStart@19083: if !sleepStopLatched: restoreParkedIptvTwinIfNeeded() for live entry,
  else rejoin if away > IPTV_LIVE_REJOIN_AFTER_MS (iptvLiveRecovery.userRetry
  ("lifecycle-rejoin") after playWhenReady=true), else player.play(); then restart
  external subtitle ticker.
- onPause@19237: ActivityTracker clear + cancelPikPakRetry. onResume@19220: retry
  pending recording publish.
- onDestroy@19270 relevant to this chunk, in order: cancelPendingIptvCatchupRequest →
  displayModeController.clear → mediaPreparationScope.cancel + generation++ →
  sourceBrowser.destroy → final sendProgress → subtitleControlsLift.cancel →
  iptvTuneDiagnostics.onSessionEnd → startup/manual/pikPakGate runnables off
  progressHandler → clearIptvTwinTrial → iptvLiveRecovery.cancel →
  unregisterNetworkCallback(iptvNetworkCallback) → RecordingRegistry.removeListener →
  cancelSleepTimer → finalizeIptvRecordingIfActive → seekFeedbackManager.destroy →
  iptvBrowseHandler clear + IPTV tokens++ → PikPak retry cancel + handler clear →
  bufferingHandler clear → upNextHandler clear → unregisterReceiver(metadataUpdateReceiver)
  → subtitleScope.cancel → skipSegmentScope.cancel → progress/controls/seekbar handlers
  clear → releaseLoudnessEnhancer → AudioEffectSession.closeCurrent → player
  removeListener(playbackListener, subtitleListener) + release (analytics listeners NOT
  removed explicitly; released with player) → null player/trackSelector/
  offsetRenderersFactory/speechTap → subtitleSeekHandler.removeCallbacks(
  subtitleSeekRunnable) → externalSubtitleHandler clear →
  SubtitleSettings.clearActiveSubtitleIdentityProvider(this) → adapters null →
  focusRecoveryHandler clear → cancelSourceSwitchWait → sendFinished → super.onDestroy.
- finish()@16674 overrides: one-shot final sendProgress snapshot + PlaybackReturnHandoff
  .markReturning before super.finish (relevant because C11 ENDED and C14 startup_back
  call finish()).
- Not explicitly cleared in onDestroy: iptvTwinTrialHandler (only its one runnable via
  clearIptvTwinTrial), sleepTimerHandler (via cancelSleepTimer), iptvReconnectPill view,
  iptvRecordingController.onAborted lambda (2910). Preserve, don't silently change.
- Auto-advance runnables in C11 (1743, 1755) post on progressHandler → cancelled by
  progressHandler.removeCallbacksAndMessages(null) in onDestroy.

---------------------------------------------------------------------------------
## 6. Existing JVM tests (android/app/src/test/kotlin/com/debrify/app/…)

Robolectric 4.15.1 is already a testImplementation (build.gradle.kts:139).
- tv/StremioTvStartupWatchdogTest.kt (Robolectric, sdk 28, PAUSED looper): drives the
  activity by REFLECTION. Field/method names from this chunk it depends on:
  startupGateView, startupGateStatus, titleView, nextOverlay, pikPakReactivationIndicator,
  payload, isIptvMode, player, playbackListener, currentIndex, stremioSources,
  currentStremioSourceIndex, startupFailoverCursor, startupFailoverTimeout,
  startupMaxAttempts, startupTryNextOnFailure, startupSourcesExhausted,
  manualSourceSwitchSnapshot, manualSourceSwitchTimeout, mediaPreparationGeneration,
  pikPakGateReprepare, recoveryCompletedItemKeys. Exercises playbackListener ENDED/error
  paths for Stremio TV + PikPak deferral (tests @101–286).
- tv/ShufflePlaybackFlowTest.kt (Robolectric, reflection): showShuffleGeneration etc.
- tv/SubtitleSyncDismissTest.kt: reflects `linePickerOverlay`, `syncOverlay`,
  `setupBackPressHandler`.
- profiles/NativePlayerSettingsConsumptionTest.kt: full `create()` of this activity
  → onCreate → setupPlayer; reads field `trackSelector` and asserts TEXT disabled under
  subtitle_forced_only; moviePlayerConsumesDefaultsAndCustomSettings (getControlsSkin).
- profiles/NativePlayerRejectedLaunchTest.kt: create() with empty Intent → finish before
  bindViews, then full start/resume/pause/stop/destroy (guards onDestroy isInitialized).
- tv/LateEpisodeMetadataMergeTest.kt: top-level mergeLateMetadata* only (not the receiver).
- tv/IptvDeviceQuirksTest.kt: IptvDeviceQuirks (iptvStartsWithStrictTs source).
- tv/StartupFailoverCursorTest.kt, audio/NativeAudioRoutingTest.kt,
  tv/SubtitleControlsLiftControllerTest.kt, profiles/NativePlayerPreferencesTest.kt:
  collaborators, not chunk logic. tv/TvSourceBrowserFocusTest.kt: sourceVisibleForEpisode
  + controller, not the activity's inline Callbacks.
- NO test for: IptvLiveRecovery class itself, IPTV twin trial, performIptvLiveRetune,
  classifyIptvError, IptvLiveLoadErrorPolicy, resume hold, READY resume-seek policy,
  onPlayerError IPTV ladder order, STATE_ENDED live/sleep/spurious guards,
  metadata receiver (handleMetadataUpdate/readStagedExtra/requestMetadataFromFlutter),
  bindViews' TvSourceBrowser callbacks, setupPlayer data-source/header resolvers,
  iptvMediaCodecSelector, LoadControl presets, androidDecoderStatus.

Gaps needing characterization before extraction (Robolectric where Activity needed):
1. Resume: READY seek-target matrix (startAtPercent retry when duration unknown;
   launchTrakt vs pendingItemTraktPercent vs pendingSeekMs; anti-yank 5 s/15 s gates;
   hold arming ≥80% rejection) — plain JVM once extracted; Robolectric + proxy player
   (StremioTvStartupWatchdogTest's ColdPlayer pattern) before.
2. Twin trial state machine: begin → judge baseline/streak/reset → accept; error/timeout
   → fail+blacklist; timeout while paused → park; onStop park / onStart restore; zap
   supersession (no blacklist). Use PAUSED looper + ShadowLooper.idleFor.
3. onPlayerError precedence for IPTV (twin-owned, auth revoke, HLS-force, behind-live,
   Stremio candidate, machine) with stale-delivery gate (playerError == null).
4. STATE_ENDED: live EOF never sends completed progress; spurious-end < 90 % ignored;
   sleep END_OF_ITEM latches.
5. Metadata receiver: staged-path validation (outside cacheDir / wrong prefix rejected,
   file not deleted), season/episode re-match of originalIndex, current-item live
   position merge, guide adoption triggers rebuild only for series.
6. IptvLiveLoadErrorPolicy retry delays (401/403/404 → TIME_UNSET, 429/503 Retry-After
   clamp 1–15 s and >4 errors cutoff, transport >15 cutoff, non-live defaults).
7. setupPlayer resolvers: activeVodHeaders applied only to matching origin (default
   port normalization), IPTV headers override UA; networkPatience timeouts VOD-only;
   heap-budget LoadControl (<48 MiB keeps stock).
8. onDestroy teardown after an IPTV launch (network callback unregistered, twin timeout
   removed) — only the rejected-launch path is covered today.

---

## AndroidTvTorrentPlayerActivity.kt — responsibility map, chunk B (lines 3000–7020)

File: android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt
Chunk boundaries: starts INSIDE `setupPlayer()` (decl @2736; body runs to 3133) and ends at the
start of `dispatchKeyEvent` @7018 (belongs to the next chunk). Constants used here live in the
companion object: USE_UNIFIED_MENU@20143, PROVIDER_PIKPAK@20170, PIKPAK_MAX_RETRIES=5@20171,
PIKPAK_METADATA_TIMEOUT_MS=10000@20172, PIKPAK_BASE_DELAY_MS=2000@20173, PIKPAK_MAX_DELAY_MS=18000@20174.
Top-level types used: PlaylistMode@20178, MovieTab@20214, SubtitleCatalogResult@20518 (+titleLine@20525,
detailLine@20529), PlaylistAdapter (setActiveIndex@20221, filterBySeason@20576), MoviePlaylistAdapter
(showGroup@21119). Lazy props outside chunk: controlsSkin@12713, dockSkinSpec@12742.

## 1. Responsibility clusters

### C0. setupPlayer tail (3000–3133) — player construction, part 2
- Load control: YouTube-merge buffers (3001–3013); network buffer preset "large"/"huge" with
  heap-budgeted `setTargetBufferBytes` (= min(96/192 MiB, largeMemoryClass/4), skip if <48 MiB) (3014–3058).
- `player = playerBuilder.build()` @3060; speed, listeners: playbackListener, decoderAnalyticsListener,
  iptvDiagAnalyticsListener; `playerView.player = player`.
- Creates `subtitleListener` (field @265) @3071 — onCues → `subtitleOverlay.setCues` unless `externalSubtitleActive`(@1290).
- Subtitle appearance sync: SubtitleSettings.synchronizeProjectedAppearance / SubtitleFontManager /
  resetSyncOffset / setActiveSubtitleIdentityProvider(this){currentSubtitleIdentity()}; applySubtitleSettings@16435.
- `applyResizeMode()`@16480, `playerView.requestFocus()`.
- IPTV only: `setKeepContentOnPlayerReset(true)`; registers `ConnectivityManager` default network callback →
  `iptvLiveRecovery.setOffline(..)`; stores `iptvNetworkCallback` (field @363) @3121.
- Reads: networkBuffer, isIptvMode@862, playbackSpeeds/playbackSpeedIndex, player@262, trackSelector@264.

### C1. Seekbar overlay key setup (3135–3144)
- setupSeekbar@3135. Field: seekbarOverlay@177. Calls hideSeekbar@8014. Callers: 2141, 8853.

### C2. Guide skin (per-dock-skin Episodes overlay) (3146–3521)
- Functions: installGuideOverlaySkin@3200, bindGuideSkinViews@3210, applyGuideLayoutManager@3229,
  applyGuideKeyOverride@3259, applyGuideTabStyle@3324, guideSkinBind@3379, updateGuideDetail@3441,
  loadGuideArt@3485, seedGuideSkinChrome@3498; props guideOverlayLayoutRes@3173, guideItemLayoutRes@3184.
- Owns (declared IN chunk): guideSkinInstalled@3157, guideGridSpan=5@3158, gdShowTitle..gdPopDesc @3159–3171.
- Reads: controlsSkin@12713, playlistView@154, playlistMode@850, playlistVisible@836,
  navigationTargetPosition@1343, payload@818, currentIndex@819, ottShowName@254.
- Calls: movePlaylistFocus, findNextFocusablePosition (C3), dp@6644, PlaybackItem.displayProgressPercent@20464.
- External callers: installGuideOverlaySkin@2510, bindGuideSkinViews@2514 (bindViews), seedGuideSkinChrome@8429 (showPlaylist).

### C3. Playlist overlay: adapters, tabs, DPAD focus engine (3523–4142)
- Functions: setupPlaylist@3523, rebuildPlaylistContent@3600, setupSeriesPlaylist@3634,
  setupCollectionPlaylist@3663, setupSeasonTabs@3684, createSeasonTab@3716, selectSeasonTab@3747,
  setupCollectionTabs@3763, setupPlaylistNavigation@3792, findNextFocusablePosition@3860,
  ensureFocusInPlaylist@3895, transferFocusToPosition@3948, movePlaylistFocus@3999,
  createMovieTab@4092, selectMovieTab@4120.
- Owns (declared outside chunk): playlistOverlay@153, playlistView@154, seasonTabsContainer@155,
  seasonTabs@173, movieTabs@174, playlistMode@850, playlistAdapter@851, seriesPlaylistAdapter@852,
  moviePlaylistAdapter@853, movieGroups@854, isNavigating@1342, navigationTargetPosition@1343,
  focusRecoveryHandler@1344, focusRecoveryRunnable@1345.
- Reads: payload, currentIndex, hasPlaylistResolver@1094, playlistVisible@836 (written by show/hidePlaylist outside),
  guideSkinInstalled/guideItemLayoutRes (C2).
- Calls out: hidePlaylist@8643, playItem (C5), requestEpisodeFetch@16993, computeMovieGroups@8555,
  applyGuide* / guideSkinBind / updateGuideDetail (C2).
- External callers: setupPlaylist@2142; rebuildPlaylistContent@2323,17414,18658; selectSeasonTab@8471;
  selectMovieTab@8480. movieGroups/playlistMode also read by C7 getShuffleEligibleIndices.

### C4. Dock (controls) skin + control button wiring (4144–4550)
- Functions: installOttControlsSkin@4144, setOttTrackHeight@4212, updateOttCaption@4230,
  clearOttCaption@4241, refreshOttCaptionFor@4250, setupControls@4255.
- Owns: ottSkinInstalled@224, ottCaptionLabel@225, ottCaptionOwner@226, ottIdentity*@227–234,
  ottQualityChips@239, ottRatingChip@240, ottMetaLine@241, ottScrubPreviewChip/Text@244–245,
  ottProgressTrackContainer@246, ottSourcesButton@250, controlsOverlay@187, pauseButton@188,
  iptvPrevButton@189, iptvNextButton@190, iptvGuideButton@191, iptvJumpButton@192,
  iptvStartOverButton@193, iptvStartOverSeekButton@194, iptvRecordButton@195,
  originalControlDockOrder@200, audio/subtitle/aspect/speed/nightMode buttons @201–205,
  debrifyTime*/debrifyProgressLine/cinemaProgress* @208–215 (bound here, driven elsewhere).
- Reads: dockSkinSpec@12742, isIptvMode, controlsMenuVisible@835, unifiedMenu@1200, sourceBrowser@1201,
  subtitleControlsLift@152, player.
- Calls out: seekBy@8113, scheduleHideControlsMenu@7614, cancelScheduledHideControlsMenu@7622,
  hideControlsMenu@7535, setupCinemaProgressBar@7735, startSeekbarProgressUpdates@7653,
  togglePlayPause@7411, showNightModeDialog@16608, updateNightModeButtonLabel@7647,
  showIptvChannelJumpDialog@11816, toggleIptvStartOver@11378, showIptvStartOverTimeline@11362,
  showAudioTrackDialog@15621, showSubtitleSettingsPanel@15808, cycleAspectRatio@16473,
  updateAspectButtonLabel@7642, cyclePlaybackSpeed@16490, showPlaylist@8419,
  nextIptvEpisode@14201, prevIptvEpisode@14206, switchToIptvChannel@12340, playNext/playPrevious/
  updateCatalogEpisodeControls (C7), showRandomPlaybackDialog (C7).
- External callers: setupControls@2143,8854,8901,9103 (re-run on reconfigure); setOttTrackHeight@7854,7893;
  refreshOttCaptionFor@7639,7644,7649,16509.
- Behaviour fact: a view holds ONE focus listener; every `extendTimerOnFocus` assignment overwrites the
  classic scale animation (comment @4527–4531); OTT re-applies its treatment LAST (4532–4549). Order is load-bearing.

### C5. Playback start pipeline (4556–4936)
- Functions: playItem@4556, resolveAndPlay@4649, discoverProtectedMime@4737, startPlayback@4754,
  playMediaDirect@4842, buildMergedSourceOrNull@4888, buildMergedSource@4919.
- Owns/writes: currentIndex@819, mediaPreparationGeneration@823 (incremented in playItem@4574 and
  discoverProtectedMime@4739), activeVodHeaders@820 (@Volatile; read by data source factory @2867),
  pendingSeekMs@824, pendingItemTraktPercent@830, isAutoAdvancing@834, hasEverBeenReady@1377,
  maxStableDurationMs@1438, lastRealPositionMs@1439, payload.items[i] (in-place URL/mime updates).
- Reads other clusters: sleepStopLatched@1282 (writes false on manual pick), pendingShufflePlayback (C7),
  startupFailoverCursor@1100, startupFailoverGeneration@1101, manualSourceSwitchIndex@1134,
  manualSourceSwitchSnapshot@1133, manualSourceCandidateUrl@1141 (write), stremioResolutionToken@1093,
  currentStremioSourceIndex@1090, protectedStreamClient@821, mediaPreparationScope@822, isIptvMode.
- Calls out: dropStaleSourceSwitchFeedback@17896, hideBufferingIndicator@19260, hideUpNextCard@8784,
  resetSkipSegmentState@8406, releaseResumeHold@1408, buildProtectedMediaOrigins@2678,
  startupLog@17784, startupSourceFields@17761, isCurrentStartupGeneration (StartupFailoverCursor.kt:23),
  failManualSourceCandidate@17367, failStartupResolution@17681, restartProgressUpdates@16651,
  ProtectedStreamHttp.needsDiscovery/discoverMimeType; in-chunk: cancelPikPakRetry (C10), shuffle guards (C7),
  requestStreamFromFlutter (C9), setResolvingState (C8), resetSubtitleState/fetchStremioSubtitles (C6),
  updateTitle (C8), playPikPakVideoWithRetry (C10).
- External callers: playItem@1746,1758,2185,8772,8776,17415,18654,18694; playMediaDirect@14379;
  buildMergedSource@18802 (YouTube quality switch).
- Fact: PikPak path (6680–6691) builds MediaItem WITHOUT setMimeType and never uses the merged
  YouTube source; direct path (4853–4873) sets mimeType and playWhenReady.

### C6. Addon/Stremio subtitle fetch + auto-select + manual identity search (4797–4840, 4940–5226, 6025–6642, 6915–7015)
- Functions: resetSubtitleState@4797, fetchStremioSubtitles@4940, seedInjectedSubtitles@5070,
  fetchStremioSubtitlesWithImdb@5098, launchAddonSubtitleFetch@5117, setAddonSubtitleSlot@5162,
  rebuildFlatStremioSubtitles@5177, retryAddonSubtitles@5192, refreshSubtitleUiForLoading@5211,
  clearStremioLoadingState@5219, showSearchSubtitleDialog@6025, getCurrentSubtitleSearchItem@6239,
  requestSubtitleCatalogSearchFromFlutter@6294, parseSubtitleCatalogResults@6334,
  createSubtitleCatalogResultAdapter@6358, showSeasonEpisodePrompt@6406, applyManualSubtitleIdentity@6506,
  resolveSeasonEpisodeForSubtitle@6565, parseSeasonEpisodeFromTitle@6575,
  buildSubtitleSearchInitialQuery@6594, buildManualSubtitleDisplayLabel@6613,
  currentSubtitleIdentityLabel@6627, tryAutoSelectAddonSubtitle@6915.
- Owns: subtitleTracks@1209, stremioSubtitleService@1213, stremioSubtitles@1214,
  addonSubtitleResults@1215, injectedSubtitles@1220, suppressSubtitleAutoSelect@1224,
  addonFetchTokens@1225, failedSubtitleUrls@1226, currentStremioSubtitleIndex@1227,
  subtitleAddonDiscoveryReady@1228, isLoadingStremioSubtitles@1229, subtitleTrackReadiness@1230,
  userManuallySelectedSubtitle@1231, addonSubtitleFetchToken@1232, manualSubtitle{ImdbId,Type,
  Season,Episode,DisplayLabel}@1233–1237, subtitleScope@1238, subtitleSearchResults/Status/
  pendingSeriesResult @14799–14801.
- Reads: payload (incl. perItemImdbIds map — WRITTEN @5051), currentIndex, trackSelector@264,
  playerPreferences@2012, offsetRenderersFactory@340, subtitleSettingsVisible@1196, unifiedMenu@1200,
  externalSubtitleActive@1290, isIptvMode, iptvChannels@863, currentIptvIndex@864, player.
- Calls out: stopExternalSubtitleRendering@16054, refreshSubtitlePanelForLoading@15860,
  isSideRenderableSubtitle@15940, loadStremioSubtitle@15951, SubtitleAutoSelection.kt pure fns
  (chooseAutomaticSubtitle, isUndeclaredHlsCaption, audioAllowsAutomaticSubtitles, selectedAudioLanguage),
  LanguageMapper, SubtitleSettings.getSubtitleSourcePriority/resetSyncOffset, requestMovieMetadataFromFlutter (C9).
- External callers: resetSubtitleState@11386,11475,11507,12389,14177,19880; fetchStremioSubtitles@2283,19938;
  clearStremioLoadingState@19881; retryAddonSubtitles@15000; tryAutoSelectAddonSubtitle@1507,16001;
  showSearchSubtitleDialog@15791,15798,15885; getCurrentSubtitleSearchItem@14872,15427,15432;
  applyManualSubtitleIdentity@15412,15429,15439; currentSubtitleIdentityLabel@14968,15799.

### C7. Navigation: next/prev + shuffle (5228–5588)
- Functions: playNext@5228, playPrevious@5283, updateCatalogEpisodeControls@5317, playRandom@5332,
  showRandomPlaybackDialog@5345, resetShuffle@5385, shuffleAttemptCurrent@5407,
  shuffleAttemptOwned@5410, restoreShufflePreparation@5415, failShufflePlayback@5421,
  watchShufflePlayback@5435, clearQueuedShuffle@5447, yieldEpisodeFetchToQueuedShuffle@5456,
  canShuffleWholeShow@5461, playShowShuffle@5469, getShuffleEligibleIndices@5550, pickShuffleIndex@5574.
- Owns: nested `private class ShufflePlaybackAttempt`@5394 (7 ctor params), pendingShufflePlayback@5403,
  queuedShuffleGeneration@5404, queuedShuffleNavigation@5405, shuffleWatchGeneration@5433 (all IN chunk);
  continuousShuffleEnabled@855, shuffleBag@856, showShuffle@857 (ShowShuffle.kt), showShuffleGeneration@858.
- Reads: payload, currentIndex, mediaPreparationGeneration (C5), sleepStopLatched, isFinishing/isDestroyed,
  episodeFetchInFlight@16988, customShuffleEpisodes@1096, hasPlaylistResolver@1094,
  hasAdjacentEpisodeResolver@1095, isStremioTvMode@1177, stremioTvChannels@1178, iptvPrevButton@189 (write visibility),
  playlistMode/movieGroups (C3), isPikPakRetrying (C10), progressHandler@1363.
- Calls out: getNextPlayableIndex@8484, getPrevPlayableIndex@8522, guideAdjacent@16971,
  requestEpisodeFetch@16993, requestAdjacentEpisodeFetch@17064, requestQuickPlayNextEpisode@17150 + finish(),
  requestStremioTvNext@19947, showStatusPillTransient@16176, hideUpNextCard@8784,
  currentPlaybackItemIsPikPak@17702, playItem/requestStreamFromFlutter (C5/C9).
- External callers: playShowShuffle/pickShuffleIndex@1739–1740 (playbackListener auto-advance), pickShuffleIndex@8706,
  failShufflePlayback@1818 (onPlayerError), watchShufflePlayback@17031, yieldEpisodeFetchToQueuedShuffle@17020,17095,17124,
  playRandom/resetShuffle@15597–15608 (unified menu), updateCatalogEpisodeControls@2152,2325,18427.
  playNext has only in-chunk callers (@4500 next button, @6781 PikPak exhaustion).

### C8. Title / dock identity / loading overlay (5590–5925)
- Functions: guideTitleFor@5590, updateTitle@5597, updateOttIdentity@5641, updateOttExtras@5760,
  dockTagsFor@5857, spellNumber@5882, setResolvingState@5899, setNextOverlayBackdrop@5911.
- Owns: dockTagsCacheKey@242, dockTagsCache@243. Writes views: titleView@143, ottEpisodeBadge@146,
  ottEpisodeTitle@147, ottRatingContainer@148, ottRating@149, channelBadge@150, nextText@157,
  nextSubtext@158, nextBackdrop@161, ottIdentity*/ottQualityChips/ottRatingChip/ottMetaLine (bound by C4).
- Reads: payload, currentIndex, controlsSkin, ottShowName@254, ottSkinInstalled.
- Calls out: fadeInNextOverlay@8656, hideNextOverlay@8663, DockFormatTags.detect, seasonEpisodeLabel@20448.
- External callers: updateTitle@2326,2443,19937; updateOttIdentity@2263,7475; setResolvingState@17381,17589;
  updateOttExtras also referenced @236 (comment) / 20444.

### C9. Flutter MethodChannel requests (5927–6023)
- requestStreamFromFlutter@5927 ("requestTorrentStream"), reportValidatedSourceCommit@5966
  ("commitStremioSource"; reads stremioSources@1089, sourcePersistenceSessionId@1119),
  requestMovieMetadataFromFlutter@5988 ("requestMovieMetadata"). (C6 also has
  requestSubtitleCatalogSearchFromFlutter "searchSubtitleCatalogs".) Stateless besides those reads.
- External callers: reportValidatedSourceCommit@17358,17559.

### C10. PikPak cold-storage retry engine (6648–6912)
- Functions: playPikPakVideoWithRetry@6652, attemptPikPakPlaybackLoop@6707, waitForPikPakMetadata@6803,
  showPikPakRetryOverlay@6873, hidePikPakRetryOverlay@6891, cancelPikPakRetry@6900.
- Owns: isPikPakRetrying@1368, pikPakRetryCount@1369, pikPakRetryId@1370, pikPakRetryHandler@1371,
  pikPakReactivationIndicator@1375, pikPakReactivationText@1376.
- Reads: player, isStremioTvMode, startupFailoverCursor, startupGateStatus@141, subtitleOverlay@151.
- Calls out: cancelPikPakGateReprepare@17705, schedulePikPakGateReprepare@17715, failManualSourceCandidate@17367,
  failStartupCandidate@17566, failShufflePlayback/playNext (C7), resetSubtitleState/fetchStremioSubtitles/
  tryAutoSelectAddonSubtitle (C6), updateTitle (C8), restartProgressUpdates@16651.
- External callers: cancelPikPakRetry@17970,18639,18793,19244(onPause),19338(onDestroy),19882; hidePikPakRetryOverlay@18843.

### Misc: dp@6644 — used ~200 times across the file (2507…16398); keep on host or make a util.

## 2. External effects per cluster
- C0: Media3 ExoPlayer build/LoadControl/listeners; ConnectivityManager.registerDefaultNetworkCallback (API≥24);
  SubtitleSettings static singletons (identity provider bound to `this`).
- C1: key listener only.
- C2: view inflation into R.id.android_tv_playlist_overlay (removeAllViews+inflate); Glide load/clear; key listener; LayoutManager swap.
- C3: RecyclerView adapters/layout managers; focusRecoveryHandler.postDelayed(100ms); playlistView.postDelayed(50/100ms);
  ViewTreeObserver OnGlobalLayoutListener (self-removing) and OnGlobalFocusChangeListener (debug log, ADDED ON EVERY
  setupPlaylistNavigation call, never removed); TextView tab creation; Log "PlaylistNav".
- C4: LayoutInflater swap of debrify_controls_root at same index inside PlayerControlView; PaintDrawable shader;
  PlayerView.setControllerVisibilityListener; View.animate() focus animations; Media3 controller.
- C5: ExoPlayer setMediaItem/setMediaSource/prepare/play; MergingMediaSource + DefaultHttpDataSource (network);
  coroutine `mediaPreparationScope.launch` + Dispatchers.IO HTTP MIME probe; MethodChannel via C9; Toast.
- C6: `subtitleScope.launch` per addon (stremioSubtitleService network); trackSelector parameter writes;
  SharedPreferences reads (playerPreferences: player_default_subtitle_language, subtitle_only_foreign_audio,
  subtitle_forced_only, player_default_audio_language); MethodChannel "searchSubtitleCatalogs"/"requestMovieMetadata";
  AlertDialogs (R.style.Theme_Debrify_SubtitleDialog) with EditText/ListView; Toasts; offsetRenderersFactory.setOffsetUs(0).
- C7: progressHandler.postDelayed (15 s shuffle watchdog; 50 ms queued-shuffle poll; post onUnavailable);
  AlertDialog; Toasts; status pill; MethodChannel via requestStreamFromFlutter; may `finish()` (quick-play hand-back).
- C8: Glide into nextBackdrop (guarded isFinishing/isDestroyed); spans; overlay fades.
- C9: MainActivity.getAndroidTvPlayerChannel()?.invokeMethod — "requestTorrentStream", "commitStremioSource",
  "requestMovieMetadata" (callbacks on Result; no runOnUiThread except searchSubtitleCatalogs).
- C10: per-call `Handler(Looper.getMainLooper())` polling every 500 ms (local, not a field); pikPakRetryHandler.postDelayed
  1500 ms → playNext; runOnUiThread overlay animations; ExoPlayer setMediaItem/prepare/play; Toast.

## 3. Coupling (cluster → cluster, in-chunk)
- C3 → C2 (layout manager, key override, tab style, row binder, detail), C3 → C5 (playItem on click).
- C2 → C3 (movePlaylistFocus, findNextFocusablePosition).
- C4 → C7 (playNext, playPrevious, updateCatalogEpisodeControls, showRandomPlaybackDialog), C4 → C8 via OTT views it binds.
- C5 → C7 (shuffleAttemptCurrent, watchShufflePlayback, restoreShufflePreparation, failShufflePlayback, pendingShufflePlayback),
  C5 → C9, C5 → C8 (setResolvingState, updateTitle), C5 → C6 (resetSubtitleState, fetchStremioSubtitles), C5 → C10.
- C7 → C5 (playItem, mediaPreparationGeneration), C7 → C9, C7 → C10 (isPikPakRetrying), C7 → C3 (playlistMode, movieGroups).
- C10 → C6, C8, C7 (playNext, failShufflePlayback).
- C6 → C9 (requestMovieMetadataFromFlutter).
- Heavy shared state: payload, currentIndex, mediaPreparationGeneration, sleepStopLatched, isAutoAdvancing.

## 4. Extraction candidates (low → high risk)
1. Pure helpers (LOW): parseSeasonEpisodeFromTitle@6575, buildSubtitleSearchInitialQuery@6594,
   buildManualSubtitleDisplayLabel@6613, parseSubtitleCatalogResults@6334, spellNumber@5882,
   dockTagsFor@5857 (needs the 2-field cache), findNextFocusablePosition logic, PikPak backoff formula (6729–6734),
   heap-budget LoadControl math (3038–3058). No host needed; directly JVM-testable.
2. C9 Flutter bridge adapter (LOW): wrap three invokeMethod calls in a `TvPlayerFlutterBridge(channelProvider)`;
   keep callback threading identical (no runOnUiThread added).
3. C2 Guide skin (LOW-MED): `TvGuideSkinController(activity/layoutInflater, controlsSkin, playlistView, glide)`;
   Host needs: payload/currentIndex snapshot, ottShowName, playlistMode, playlistVisible, navigationTargetPosition,
   movePlaylistFocus(delta), findNextFocusablePosition, dp(). Owns gd* fields. Must still run before playlist findViewById (bindViews@2510).
4. C8 identity/dock text (MED): `TvDockIdentityPresenter`; host: current item, contentType, ottShowName, controlsSkin,
   guideTitleFor, view refs (from C4). setResolvingState/backdrop needs isFinishing/isDestroyed + fade fns.
5. C10 PikPak retry engine (MED): `PikPakColdStorageRetry` owning retryId/count/flag/handler + polling handler.
   Callbacks: player(), isStremioTvMode, onPlaybackStart(item) (setMediaItem/prepare/play + title/progress/subtitle side effects),
   onLoaded() (tryAutoSelect), onExhausted() returning routing (shuffle → manual → startup → toast+1.5s playNext),
   schedule/cancelPikPakGateReprepare, show/hide overlay, startupGate status mirror.
   Tests reflect on `cancelPikPakRetry`, `waitForPikPakMetadata`, `pikPakReactivationIndicator` — must keep activity shims.
6. C3 Playlist focus engine (MED-HIGH): `TvPlaylistController(playlistView, seasonTabsContainer, Callbacks)`;
   Callbacks: onPlay(index), onFetchEpisode(s,e), hidePlaylist(), isVisible, guide-skin hooks, computeMovieGroups.
   Timing-sensitive (50/100 ms posts, isNavigating, global layout listener); playlistMode/movieGroups read by shuffle.
7. C6 Addon subtitles + search dialog (HIGH): many token guards (addonSubtitleFetchToken, addonFetchTokens),
   trackSelector writes, shared with ~30 functions outside chunk (panel/unified menu/loadStremioSubtitle).
   Natural seam = existing SubtitlePanelController/UnifiedMenuController neighbours; search dialog (6025–6505) is the
   lowest-risk sub-piece (needs getCurrentSubtitleSearchItem + applyManualSubtitleIdentity callbacks).
8. C4 setupControls (HIGH): focus-listener last-wins ordering, re-entrant (4 callers), binds ~30 fields used everywhere.
9. C5 + C7 playback start + shuffle (HIGHEST): interleaved generation guards (mediaPreparationGeneration,
   showShuffleGeneration, stremioResolutionToken, startupFailoverGeneration, manual token), sleep-latch, resume
   policy; Robolectric reflection tests and Dart source-text tests pin names/locations. Extract last, as one unit.

## 5. Lifecycle / teardown facts
- onPause@19237: cancelPikPakRetry() (bumps pikPakRetryId, clears pikPakRetryHandler, cancels gate reprepare, hides overlay).
- onDestroy@19270 (in this order): mediaPreparationScope.cancel()@19274; pikPakGateReprepare removed from
  progressHandler@19297; iptvLiveRecovery.cancel()@19306; iptvNetworkCallback unregister@19310 / =null@19313;
  pikPakRetryHandler.removeCallbacksAndMessages(null)@19339 (+ indicator animate().cancel()/GONE right after);
  subtitleScope.cancel()@19363; progressHandler.removeCallbacksAndMessages(null)@19376 (kills shuffle watchdog +
  queued-shuffle polls); player.removeListener(playbackListener)@19391, subtitleListener removed, release()@19393;
  focusRecoveryHandler.removeCallbacksAndMessages(null)@19423 + focusRecoveryRunnable=null@19424.
- NOT cancelled on destroy: waitForPikPakMetadata's local Handler (self-terminates only via pikPakRetryId mismatch or
  timeout ≤ 10 s+18 s; cancelPikPakRetry bumps the id so the next tick exits); playlistView.postDelayed lambdas;
  OnGlobalFocusChangeListener instances accumulated per rebuildPlaylistContent.
- Guards relying on lifecycle: discoverProtectedMime checks isFinishing/isDestroyed/sleepStopLatched; shuffleAttemptOwned
  checks isFinishing/isDestroyed; setNextOverlayBackdrop/showPikPakRetryOverlay/hidePikPakRetryOverlay check
  isFinishing/isDestroyed (Glide crash guard); MethodChannel callbacks (C9) have NO lifecycle guard themselves — callers
  rely on mediaPreparationGeneration / addonSubtitleFetchToken / dialog.isShowing.
- playItem ordering (must be preserved): shuffle-attempt check → restorePreparation capture → pendingShufflePlayback=null →
  ++mediaPreparationGeneration → watchShufflePlayback → sleep latch gate → bounds → dropStaleSourceSwitchFeedback →
  buffering/upnext/skip resets → cancelPikPakRetry → currentIndex/controls/activeVodHeaders → releaseResumeHold →
  pendingSeekMs/pendingItemTraktPercent → resolve or start.
- PikPak exhaustion order: cancelPikPakGateReprepare → clear state → failShufflePlayback → failManualSourceCandidate →
  failStartupCandidate (if uncommitted) → toast + 1.5 s playNext.

## 6. Existing JVM tests touching this chunk (android/app/src/test/kotlin/com/debrify/app/…)
- tv/ShufflePlaybackFlowTest.kt (Robolectric, reflection): watchShufflePlayback, failShufflePlayback,
  shuffleAttemptCurrent, resetShuffle, yieldEpisodeFetchToQueuedShuffle, clearQueuedShuffle; fields
  queuedShuffleGeneration/Navigation, episodeFetchInFlight, mediaPreparationGeneration, showShuffleGeneration;
  nested class simpleName "ShufflePlaybackAttempt" with a 7-arg ctor. Renames/moves break it.
- tv/StremioTvStartupWatchdogTest.kt (Robolectric, reflection): cancelPikPakRetry, waitForPikPakMetadata(item,0,0,0L,cb),
  schedulePikPakGateReprepare, fields payload, currentIndex, pikPakReactivationIndicator, pikPakGateReprepare, player,
  titleView, startupGateStatus.
- profiles/NativePlayerSettingsConsumptionTest.kt: reads `trackSelector`, `payload`, `getControlsSkin` on this activity
  (resetSubtitleState reflection is on TorboxTvPlayerActivity, not this one); verifies forced-only disables text tracks at create.
- audio/NativeAudioRoutingTest.kt: source-text check of this file for setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true) (outside chunk).
- Pure-helper tests already covering called code: SubtitleAutoSelectionTest, SubtitleSourcePriorityTest,
  ForcedSubtitlePolicyTest, SubtitleAudioPolicyTest, ShowShuffleTest, ProtectedStreamHttpTest, StartupFailoverCursorTest,
  TvControlsSkinTest, PlaybackItemHeadersTest.
- Dart source-text tests that pin THIS chunk's text/location (repo test/):
  - test/android_tv_auto_advance_resume_test.dart: `_between('private fun playItem(', 'private fun resolveAndPlay(')`
    must contain the pendingSeekMs/pendingItemTraktPercent expressions.
  - test/manual_source_validation_contract_test.dart: `_between('private fun resolveAndPlay(', 'private fun startPlayback(')`
    must contain 'reason=stale_manual_token' and 'failManualSourceCandidate("initial-resolve")'.
  Moving playItem/resolveAndPlay/startPlayback out of the file or reordering them breaks these.

### Gaps needing Robolectric characterization before extraction
- C3 focus engine: movePlaylistFocus boundary/rapid-press (navigationTargetPosition), header skipping, season/movie tab
  selection + scroll, ensureFocusInPlaylist middle-out recovery, guide-skin vertical/grid key remap (escape to tabs/rail).
- C2: guideItemLayoutRes/overlay per skin, guideSkinBind status text (BROADCAST FETCH/ON AIR/CLEARED/% IN), seedGuideSkinChrome captions.
- C4: setupControls focus-listener final state per skin (classic vs OTT), button click routing (unified menu vs dialogs, IPTV vs catalog next/prev),
  controller-visibility reconcile → hideControlsMenu + subtitle lift restore.
- C5: playItem sleep-latch suppression, resume suppression matrix (auto-advance/suppressResume/suppressTrakt), stale resolve
  rejection (generation/startup/manual token), PikPak vs direct routing, MIME discovery re-entry, merged-source fallback.
- C6: addon fan-out token supersession (content switch vs single-addon retry), rebuildFlatStremioSubtitles re-pinning,
  perItemImdbIds caching incl. null, injected captions path, manual identity search flow, resetSubtitleState fields.
- C7: playNext fallback ladder (shuffle → next index → Stremio TV → guide fetch → adjacent fetch → quick-play finish → toast),
  playPrevious suppressResume, updateCatalogEpisodeControls visibility, pickShuffleIndex bag behaviour, playShowShuffle
  queued-while-fetching and 3-attempt cap.
- C8: updateOttIdentity per skin text, updateOttExtras chips/meta/TICKET overline, dockTagsFor URL fallback.
- C10: retry schedule (0, 2, 4, 8, 16, 18 s caps) and exhaustion routing order; success clears overlay; onPause cancel.

---

## AndroidTvTorrentPlayerActivity.kt — responsibility map, chunk C (lines 7017–10600)

File: android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt (revision 39c630303).
The chunk ends at 10600, the closing brace of `showIptvCategoryPicker`. The nested `IptvCategoryAdapter` starts at 10602, outside the chunk.
Companion constants are at 20155–20167: UP_NEXT_THRESHOLD_MS, UP_NEXT_MIN_DURATION_MS, UP_NEXT_TICK_MS, CONTROLS_AUTO_HIDE_DELAY_MS, SEEK_STEP_MS, SEEK_LONG_PRESS_THRESHOLD=3, MAX_SKIP_SEGMENT_CACHE_ENTRIES=64 and IMDB_ID_REGEX.
Some fields are declared mid-file, not in 136–1400: gdPop@3168, iptvZapBannerDocked@12681, guideStyle@12698 (lazy), guideTokens@12706 (lazy), dockSkinSpec@12742 (lazy), legacyStoragePermissionRequestCode@19205, notificationPermissionRequestCode@19206. Several fields/vals are also declared inside this chunk; they are listed per cluster below.

---------------------------------------------------------------------------
## 1. Responsibility clusters

### A. Key dispatcher + focus probes — 7017–7401
- Members: dispatchKeyEvent@7018 (to 7379), isFocusInControlsOverlay@7381, isFocusInIptvChannelList@7392.
- Owns: iptvUpPressActive@198 and iptvUpLongPressHandled@199. Only this cluster writes them (7293–7309).
- Reads: startupGateView@140, linePickerOverlay@1199, syncOverlay@1198, subtitlePanel@1197, sourceBrowser@1201, unifiedMenu@1200, isIptvMode@862, iptvChannels@863, currentIptvIndex@864, iptvZapPagingActive@1024, iptvGuideVisible@1008, iptvEpgVisible@1070, iptvEpgEntry@1071, iptvChannelAdapter@1007, iptvGuideList@994, iptvGuideSearch@995, stremioTvGuideVisible@1189, stremioTvGuideSearch@1181, seekbarVisible@837, playlistVisible@836, upNextVisible@169, controlsMenuVisible@835, skipSegmentButton@168, stremioSourceBadge@1091, cinemaProgressContainer@215, pauseButton@188, player@262, stremioSources (field), cinemaSeekMode@256, isStremioTvMode@1177, stremioTvChannels, playlistMode@850, controlsOverlay@187.
- External reference: isFocusInControlsOverlay is also called by hideControlsRunnable@1484.

### B. Controls overlay / dock presentation + play/pause — 7403–7650
- Members: handlePlayPauseToggleFromCenter@7403, togglePlayPause@7411, showControlsMenu@7443, hideControlsMenu@7535, updateSubtitleControlsLift@7589, hideTitleImmediately@7605, scheduleHideControlsMenu@7614, cancelScheduledHideControlsMenu@7622, updatePauseButtonLabel@7626, updateAspectButtonLabel@7642, updateNightModeButtonLabel@7647.
- Owns:
  - controlsMenuVisible@835. Written only at 7506 and 7555.
  - controlsHandler@1364 and hideControlsRunnable@1484 (shared with D at 7730).
  - Title views: titleContainer@142, titleView@143, titleOttContainer@145.
- Writes:
  - sleepStopLatched@1282 (G; reset at 7417).
  - subtitleControlsLift@152 (liftAbove/restore).
- Reads: payload@818, currentIndex@819, ottSkinInstalled@224, dockSkinSpec@12742, iptvZapBanner@12662, iptvZapBannerDocked@12681, startupGateView, resizeModeLabels@1354/resizeModeIndex@840, nightModeLabels@1360/nightModeIndex@842, iptvLiveRecovery@369, aspectButton@203, nightModeButton@205.

### C. Progress ticker (premium seekbar progress) — 7652–7719
- Members: startSeekbarProgressUpdates@7653, stopSeekbarProgressUpdates@7658 (no callers anywhere), updateSeekbarProgress@7662.
- Owns: seekbarHandler@1365 and seekbarProgressRunnable@1492, which re-posts itself every 100 ms.
- Writes:
  - maxStableDurationMs@1438 and lastRealPositionMs@1439. playItem@4606–4609 also resets these. They feed scrobble/completion logic outside the chunk.
  - debrifyTimeCurrent@209, debrifyTimeTotal@210, debrifyTimeDisplay@208, debrifyProgressLine@211, cinemaProgressBuffered@212.
- Reads: cinemaSeekMode (D), ottSkinInstalled.
- Calls F: updateSkipSegmentState on every tick.

### D. Cinema interactive progress bar (scrub) — 7721–7979
- Members: showControlsAndFocusProgressBar@7725, setupCinemaProgressBar@7735 (installs focus and key listeners), enterCinemaSeekMode@7790, exitCinemaSeekMode@7868, confirmCinemaSeek@7905, updateCinemaSeekSpeed@7913, updateCinemaProgressUI@7918.
- Owns: cinemaSeekMode@256, cinemaSeekWasPlaying@257, cinemaLastAnimatedProgress@259, cinemaProgressAnimator@258, cinemaProgressTrackWidth@255, cinemaProgressThumb@217, cinemaSpeedIndicator@218, cinemaProgressBackground@216, ottScrubPreviewChip@244, ottScrubPreviewText@245.
- Shares with E: seekbarPosition@838, videoDuration@839, currentSeekSpeed@184.
- External writes to D state: updateIptvControlPresentation@9717–9720 (cluster L) writes cinemaSeekMode, cinemaSeekWasPlaying, the thumb and the speed indicator directly. It does not call exitCinemaSeekMode, so playback is not resumed there.

### E. Legacy seekbar overlay + quick seek — 7981–8133
- Members: showSeekbar@7982, hideSeekbar@8014, confirmSeekPosition@8029, getAcceleratedSeekStep@8036 (also used by D), seekBackward@8045, seekForward@8054, updateSeekSpeed@8063, updateSeekbarUI@8074, updateSeekbarPosition@8094, seekBy@8113.
- Owns: seekbarVisible@837, seekbarOverlay@177, seekbarProgress@178, seekbarHandle@179, seekbarCurrentTime@180, seekbarTotalTime@181, seekbarSpeedIndicator@182, seekbarBackgroundWidth@183.
- Dead code: **showSeekbar has no caller** (its only occurrence is 7982), and it is the only writer that sets `seekbarVisible = true` (8005). As a result, dispatcher branch A6 and seekBackward, seekForward and confirmSeekPosition are unreachable. hideSeekbar has one external caller (setupSeekbar@3139) and returns early because seekbarVisible is never true.
- seekBy is live code. Its callers are dispatcher LEFT/RIGHT (A) and installOttControlsSkin@4195/4199. It uses seekFeedbackManager@815.

### F. Skip intro/credits segments — 8135–8331 and 8406–8416
- Members: currentSkipSegmentRequest@8135, updateSkipSegmentState@8164, ensureSkipSegments@8199, presentSkipSegment@8257, skipActiveSegment@8307, resetSkipSegmentState@8406.
- Owns: skipSegmentScope@1251 (Main + SupervisorJob), skipSegmentFetchJob@1252, skipSegmentFetchGeneration@1253, loadedSkipSegmentKey@1254, loadingSkipSegmentKey@1255, skipSegments@1256, activeSkipSegment@1257, skipFocusOfferedKey@1258, skipSegmentCache@1259 (bounded at 64, evicts the first key), and the SkipSegmentRequest data class@1243.
- Reads:
  - skipSegmentsEnabled@848, skipSegmentProviderId@849, hasEverBeenReady@1377, isIptvMode, payload, currentIndex.
  - upNextVisible (J), controlsMenuVisible (B), playlistVisible (H), seekbarVisible (E).
  - Visibility of all five overlay controllers (subtitlePanel, unifiedMenu, sourceBrowser, syncOverlay, linePickerOverlay).
- View: skipSegmentButton@168. Its click handler, skipActiveSegment, is bound in bindViews@2524.

### G. Sleep timer + screen hold — 8333–8404
- Members: sleepTimerMinutesLeft@8336, sleepTimerValueLabel@8342, startSleepCountdown@8348, armSleepAtEndOfItem@8361, cancelSleepTimer@8367, fireSleepTimer@8380, releaseScreenForSleep@8395, holdScreenForPlayback@8401.
- Owns: the SleepTimerMode enum@1268, sleepTimerMode@1269, sleepTimerDeadlineElapsedMs@1270, sleepTimerHandler@1271, sleepTimerRunnable@1272, sleepTimerMinuteOptions@1273, sleepStopLatched@1282.
  - B writes sleepStopLatched at 7417.
  - playbackListener writes sleepStopLatched at 1682/1717, which are the END_OF_ITEM handling in STATE_ENDED.
- External callers:
  - umPlaybackModel@15565 calls sleepTimerValueLabel at 15568, cancelSleepTimer at 15576, startSleepCountdown at 15580 and armSleepAtEndOfItem at 15589.
  - playbackListener calls cancelSleepTimer at 1681/1716, releaseScreenForSleep at 1683/1718 and holdScreenForPlayback at 1805.
  - onDestroy calls cancelSleepTimer at 19318.

### H. Playlist overlay + item navigation — 8418–8647
- Members: showPlaylist@8419, alignSeriesTabsForCurrentEpisode@8464, alignMovieTabsForCurrentItem@8475, getNextPlayableIndex@8484, getPrevPlayableIndex@8522, computeMovieGroups@8555 (pure apart from reading payload.collectionGroups), hidePlaylist@8643.
- Owns: playlistVisible@836, playlistOverlay@153, playlistView@154.
- Reads: playlistMode@850, playlistAdapter@851, seriesPlaylistAdapter@852, moviePlaylistAdapter@853, movieGroups@854, seasonTabs@173, payload (nextEpisodeMap/prevEpisodeMap/collectionGroups/items), currentIndex, gdPop@3168 (written GONE).
- External callers:
  - getNextPlayableIndex: playbackListener@1752, playNext@5239.
  - getPrevPlayableIndex: playPrevious@5285, updateCatalogEpisodeControls@5323.
  - computeMovieGroups: setupCollectionPlaylist@3664.
  - hidePlaylist: setupSeriesPlaylist@3645/3652, 3672, setupBackPressHandler@19181.
  - showPlaylist: setupControls@4492.

### I. "Next" overlay (auto-advance toast) — 8649–8670
- Members: showNextOverlay@8650, fadeInNextOverlay@8656, hideNextOverlay@8663.
- Owns the views nextOverlay@156, nextText@157 and nextSubtext@158.
- External callers:
  - playbackListener@1742–1756 shows the overlay, then progressHandler.postDelayed 1500 hides it and calls playItem.
  - setResolvingState@5903/5905.
  - requestStremioTvNext@19970–20033.

### J. Up Next card — 8672–8796
- Members: isCleanPlaybackState@8677, maybeShowUpNext@8691, the upNextTicker val@8713 (a Runnable), showUpNextCard@8744, triggerUpNext@8771, dismissUpNext@8779, hideUpNextCard@8784.
- Owns: upNextVisible@169, upNextTargetIndex@170, upNextDismissedForIndex@171, upNextHandler@172, upNextCard@164, upNextPoster@165, upNextTitle@166, upNextCountdown@167.
- Writes isAutoAdvancing@834 (in triggerUpNext).
- Reads:
  - The visibility flags of B, E, H and O (controlsMenuVisible, seekbarVisible, playlistVisible, iptvGuideVisible, stremioTvGuideVisible).
  - The five overlay controllers, nextOverlay (I) and pikPakReactivationIndicator@1375.
  - continuousShuffleEnabled@855, isIptvMode, isStremioTvMode, currentIndex, payload.
- External callers:
  - maybeShowUpNext: progressRunnable@1451/1454, about every PROGRESS_INTERVAL_MS.
  - hideUpNextCard: playItem@4611, playShowShuffle@5509.

### K. IPTV mode bootstrap + payload parsing — 8798–9096
- Members: initIptvMode@8802, parseIptvSources@8919, parseIptvLists@8939, parseStringList@8951, parseIptvChannels(JSONArray)@8957, parseIptvChannels(List<*>)@9004, iptvChannelEntry@9047.
- initIptvMode writes:
  - Mode and decoder: isIptvMode@862, iptvDecoderMode@1152.
  - Source context: iptvSourceId@1016, iptvSourceName@1017, iptvContentType@1018, iptvSelectedCategory@1019, iptvSources@1010, iptvLists@1014, iptvCategories@1015.
  - Zap context: iptvZapSourceId@1026, iptvZapSourceName@1027, iptvZapContentType@1028, iptvZapCategory@1025, iptvZapCategories@1029, iptvZapOwnsUiContext@1037.
  - Channels: iptvChannels@863 (mutates channel.sourceId/sourceName and isCurrent), iptvBrowseChannels@1009, currentIptvIndex@864.
  - Audio memory: iptvSeriesAudioKey@875, iptvPreferredAudioLang@876.
  - Services: seekFeedbackManager@815, stremioSubtitleService@1213.
  - About 22 guide/EPG view refs (iptvGuideOverlay@993 … iptvEpgList@1065; full list at 8874–8896).
- Caller: onCreate@2098 (`mode=="iptv"` returns early before parsePayload).
- parseIptvChannels(List) external callers: requestIptvBrowse@10948, requestIptvChannelJump@11901, requestIptvZapPage@12043. The parsers are pure apart from the class context.

### L. IPTV live/VOD control dock skin — 9098–9231 and 9678–9811
- Members: setupIptvControls@9098, liveIptvDockButtons@9138, applyLiveIptvControlStyle@9168, restoreCinemaDockIconTints@9218, updateIptvControlPresentation@9678, arrangeLiveIptvControlDock@9733, restoreOriginalControlDockOrder@9756, replaceControlDockOrder@9765, restoreCinemaIptvControlStyle@9778.
- Owns: cinemaIconTints@9157 and cinemaButtonTypefaces@9158, both declared in the chunk.
- Reads: originalControlDockOrder@200 (populated elsewhere), guideTokens/guideStyle, iptvStartOverActive@865, iptvStartOverTimelineVisible@867.
- Dock buttons it re-styles: audio@201, subtitle@202, aspect@203, speed@204, night@205, pause@188, iptvPrev@189, iptvNext@190, iptvGuide@191, iptvJump@192, iptvStartOver@193, iptvStartOverSeek@194, iptvRecord@195.
- Writes D state (see D).
- updateIptvControlPresentation external callers: performIptvLiveRetune@434, playbackListener@1880, showIptvStartOverTimeline@11370, toggleIptvStartOver@11385, updateIptvEpisodeControls@14215.

### M. IPTV recording (engine/tee/scheduling) — 9233–9676
- Members:
  - Availability and state: recordingEngineEnabled (lazy val@9244), recordingRegistryListener (val@9254), canRecordCurrentIptv@9343, updateRecordButtonState@9357.
  - URL classification: isSegmentedStreamUrl@9264, isCurrentIptvSegmented@9274, xtreamTsTwin@9286, engineRecordableUrl@9302, isSchedulableStreamUrl@9319, engineTaskIdForCurrentChannel@9329, recordingResourceFor@9335.
  - Actions: toggleIptvRecording@9376, maybeAskNotificationPermission@9420, toggleEngineRecording@9437, promptScheduleRecording@9538, finalizeIptvRecordingIfActive@9654.
  - Naming helpers: sanitizeRecordingName@9667, recordingTimestamp@9674.
- Owns: iptvRecordingController@197 (lazy tee) and iptvRecordButton@195 state.
- Reads: currentIptvStreamUrl@992, iptvHlsForcedUrls@888, currentIptvHttpHeaders@883, iptvChannels, currentIptvIndex, iptvSources, iptvSourceId.
- The pure candidates are isSegmentedStreamUrl, xtreamTsTwin and sanitizeRecordingName. engineRecordableUrl and isSchedulableStreamUrl are pure given iptvHlsForcedUrls.
- External callers:
  - updateRecordButtonState: 479, setupPlayer@2911, setIptvMediaItem@14386, retryIptvAsHlsIfUnrecognized@14462, onRequestPermissionsResult@19216, recordingRegistryListener.
  - finalizeIptvRecordingIfActive: 478, setIptvMediaItem@14289, beginIptvPlayback@14484, onStop@19141, onDestroy@19322.
  - isCurrentIptvSegmented: performIptvLiveRetune@451/462.

### N. IPTV guide overlay construction + styling — 9813–10183
- Members: setupIptvOverlay@9813 (to 10037), applyGuideStyle@10044.
- Creates iptvChannelAdapter@1007 and iptvEpgAdapter@1066, and installs the RecyclerView layout managers and scroll listener, the search TextWatcher/focus/editor listeners and 14 nav/day-tab click listeners.
- Reads: iptvZapPagingActive, iptvGuideUsesZapWindow@1035, iptvZapRequestInFlight@1032, iptvLists, iptvSources, iptvContentType, iptvEpgEntry, guideTokens, guideStyle.
- Caller: initIptvMode only (8898).

### O. IPTV guide visibility + browse/search context — 10185–10600
- Members: isIptvSeriesSentinel@10185, showIptvGuide@10188, hideIptvGuide@10214, beginIptvAllCategorySearch@10230, restoreIptvCategoryAfterSearch@10260, commitIptvAllCategorySearch@10294, clearIptvAllCategorySearchState@10299, focusCurrentIptvGuideRow@10308, toggleIptvGuide@10319, refreshIptvBrowserChrome@10323, updateIptvCatalogControlVisibility@10343, iptvGuideItemCountLabel@10357, selectIptvContentType@10369, selectIptvSource@10382, showIptvSourcePicker@10404, showIptvCategoryPicker@10416.
- Owns: iptvGuideVisible@1008, iptvAllCategorySearchActive@1041, iptvSearchSaved{Category@1042, Channels@1043, Categories@1044, UsesZapWindow@1045, ZapOwnsUiContext@1046}.
- Writes zap/browse state that belongs outside the chunk:
  - iptvUiContextToken@1036, iptvBrowseToken@1020, iptvZapRequestToken@1031 (all bumped).
  - iptvZapRequestInFlight@1032, iptvZapPendingInputs@1033 (cleared).
  - iptvZapOwnsUiContext@1037, iptvGuideUsesZapWindow@1035, iptvSelectedCategory, iptvCategories, iptvBrowseChannels, iptvSourceId, iptvSourceName, iptvContentType.
- Reads: iptvZapCategoryTotal@1030, iptvZapPagingActive.
- External callers:
  - hideIptvGuide: requestIptvCatchup@11461/11506, setupBackPressHandler@19175, and L@9715.
  - commitIptvAllCategorySearch: 11460, 11505, beginIptvCategoryZapSession@11683, zapIptvChannel@12553.
  - refreshIptvBrowserChrome: 10834, 10967, 11692, 11755, 11813, 12131, 12166, 12543.

---------------------------------------------------------------------------
## 2. External effects per cluster

- **MethodChannel:** no cluster calls `invokeMethod` directly; the chunk reaches Flutter only through out-of-chunk functions.
  - O and N reach it through requestIptvBrowse@10912, which calls `MainActivity.getAndroidTvPlayerChannel().invokeMethod` at 10919/10936.
  - G reaches it through sendProgress@16801 (fireSleepTimer@8383).
  - J and H reach it through playItem@4556.
- **Broadcasts:** none in the chunk.
- **A:** focus traversal; `super.dispatchKeyEvent`; delegates to the overlay controllers' `dispatchKey`; `unifiedMenu.handleEditModeKey`.
- **B:**
  - Media3: `player.pause/play/playWhenReady`, `iptvLiveRecovery.userRetry("play-press")` (7434), `playerView.showController()` (7449).
  - Timers: `controlsHandler.postDelayed(hideControlsRunnable, 4000)`.
  - View work: ViewPropertyAnimator (300/250 ms with withEndAction), `pauseButton.post{requestFocus}`, and `dock.post` re-measure in updateSubtitleControlsLift.
- **C:** `seekbarHandler.post` loop every 100 ms; reads `player.currentPosition/duration/bufferedPosition`; LayoutParams relayout.
- **D:**
  - Media3: `player.pause/play/seekTo`; `releaseResumeHold()` (1408) before seeking.
  - Animation: a ValueAnimator (80 ms) is stored in cinemaProgressAnimator, plus thumb ViewPropertyAnimators.
  - Timer: `controlsHandler.postDelayed({focus}, 100)` (7730) is not cancelled by cancelScheduledHideControlsMenu.
- **E:**
  - Media3: `player.seekTo`; releaseResumeHold.
  - UI: Toast (7989, dead path); `seekFeedbackManager.showSeekForward/Backward`; `findViewById(R.id.seekbar_background).post`.
- **F:**
  - Network: a coroutine on skipSegmentScope with `withContext(IO) TvSkipSegmentClients.fetch(...)`. Errors are logged at warning level and the result is EMPTY. A generation check plus a request-key check then rejects stale results.
  - Media3: `player.seekTo`; releaseResumeHold.
  - Focus: `button.post{requestFocus}`, and `playerView.requestFocus()` when hiding a focused button.
- **G:**
  - Timer: `sleepTimerHandler.postDelayed` (minutes). Uses `SystemClock.elapsedRealtime`.
  - Window: `FLAG_KEEP_SCREEN_ON` clear/add plus `playerView.keepScreenOn`.
  - Toasts. fireSleepTimer calls sendProgress, then `player.pause()`.
- **H:** `playlistView.post` then `postDelayed(100)` focus; Log.d lines (tags PlaylistNav and AndroidTvPlayer); selectSeasonTab@3747 / selectMovieTab@4120.
- **I:** ViewPropertyAnimator only.
- **J:** `upNextHandler` ticker every UP_NEXT_TICK_MS (500 ms); `Glide.with(this)` poster load (8756); playItem (Media3 prepare, outside the chunk).
- **K:** Calls bindViews@2486, setupPlayer@2736 (creates ExoPlayer), setupSeekbar@3135, setupControls@4255, setupBackPressHandler@19161 and setupMetadataReceiver@2188 (a receiver, outside the chunk). Also constructs SeekFeedbackManager and StremioSubtitleService, and calls playIptvChannel@14170 and bootstrapInitialIptvZapPaging@11749.
- **L:** View re-parenting (`dock.removeAllViews` / `addView`), background drawables and TextViewCompat tints.
- **M:**
  - Preferences:
    - `ProfilePreferenceProjection.getBoolean("recording_engine_enabled")` (lazy, fixed per launch).
    - `getSharedPreferences("debrify_permissions").notification_permission_asked` (read and write).
    - `ProfilePreferenceProjection.activeJobContext` / `jobAuthorizationValid(..."recordings", allowRevisionDrift=true)`.
  - Services: `startService(ACTION_STOP)`, `ContextCompat.startForegroundService(LiveRecordingService.buildStartIntent…)`.
  - Recording state: `RecordingRegistry.taskIdForUrl` / `.live`; `RecordingScheduleStore.findDuplicate/peakOverlap/overlappingTitles/put`; `RecordingAlarmReceiver.exactAlarmsGranted/registerAll`.
  - Permissions: `ActivityCompat.requestPermissions` (POST_NOTIFICATIONS, WRITE_EXTERNAL_STORAGE).
  - Dialog: AlertDialog (9602).
  - Tee recorder: `iptvRecordingController.start/stop` (the tee; file IO inside the controller).
- **N:** Creates the RecyclerView adapters; the scroll listener calls prefetchIptvZapPage@12190 (zap paging network via the bridge). The adapter callbacks route to:
  - requestIptvBrowse, switchToIptvChannel@12340, beginIptvCategoryZapSession@11682, disableIptvZapPaging@12247;
  - showIptvListPicker@10682, toggleIptvFavorite@11008, ensureIptvChannelEpg@11049;
  - requestIptvCatchup@11401, selectIptvEpgDay@11245.
- **O:** `iptvBrowseHandler.post{trimHiddenIptvZapWindow()}` (10222); `iptvGuideList.postDelayed(150)` focus; AlertDialogs (10408, 10578) with a programmatic view tree and SOFT_INPUT_STATE_ALWAYS_VISIBLE; requestIptvBrowse.

---------------------------------------------------------------------------
## 3. Coupling

### dispatchKeyEvent@7018 branches, in evaluation order
| # | Lines | Condition | Routes to |
|---|---|---|---|
| A1 | 7020–7025 | startupGateView visible and a D-pad/OK/Enter key | super (startup gate, outside the chunk) |
| A2 | 7028–7030 | linePickerOverlay visible | linePickerOverlay.dispatchKey (subtitle controller) |
| A3 | 7033–7035 | syncOverlay visible | syncOverlay.dispatchKey |
| A4 | 7038–7040 | subtitlePanel visible | subtitlePanel.dispatchKey (SubtitlePanelController) |
| A4b | 7042–7044 | sourceBrowser visible | sourceBrowser.dispatchKey |
| A5 | 7050–7057 | unifiedMenu visible | edit mode: handleEditModeKey, otherwise super; else dispatchKey, otherwise super |
| A5b | 7064–7074 | live IPTV, CH_UP/DOWN, (>1 channel or zap paging) | zapIptvChannel@12549 (first press only); always consumes |
| A5c | 7077–7126 | iptvGuideVisible | see guide sub-branches below; otherwise super |
| A5d | 7129–7150 | stremioTvGuideVisible | BACK: hideStremioTvGuide@19568; LEFT in list: consumed; long-UP: stremioTvGuideSearch focus; otherwise super |
| A6 | 7153–7177 | seekbarVisible | E: seekBackward/seekForward/confirmSeekPosition/hideSeekbar; consumes all keys. **Unreachable (see E).** |
| A7 | 7180–7186 | playlistVisible | BACK: hidePlaylist (H); otherwise super |
| A8 | 7191–7205 | upNextVisible | OK: triggerUpNext; BACK: dismissUpNext; any other key: hideUpNextCard and **falls through** (J) |
| A9 | 7207–7210 | controlsMenuVisible and BACK | hideControlsMenu (B) |
| A10 | 7215–7231 | CENTER/ENTER | focus on skipSegmentButton, stremioSourceBadge or in the controls: super. Otherwise handlePlayPauseToggleFromCenter (B) on the first press |
| A11 | 7234–7259 | DOWN | on the badge with controls open: focus cinemaProgressContainer or pauseButton. Controls hidden, or focus outside them: showControlsMenu + scheduleHideControlsMenu. Otherwise super |
| A12 | 7262–7329 | UP | see UP sub-branches below |
| A13 | 7332–7355 | RIGHT | in controls: super. isLiveIptvZapContext@12522: zapIptvChannel(1). repeat≥3: showControlsAndFocusProgressBar (D). First press: seekBy(+10 s) (E) |
| A14 | 7357–7376 | LEFT | mirror of A13 with -1 / -10 s |
| A15 | 7378 | anything else | super |

A5c (iptvGuideVisible) sub-branches:
- BACK: hideIptvEpgPane@11293 and list focus, or hideIptvGuide (O).
- LEFT in the EPG panel (isFocusInIptvEpgPanel@11539): hideIptvEpgPane and refocus the channel row. LEFT in the channel list: consumed.
- RIGHT in the channel list (first press): showIptvSchedulePane@11153 for focusedIptvGuideEntry@11140.
- UP long-press (repeat≥3) in the list: focus iptvGuideSearch.

A12 (UP) sub-branches:
1. Progress bar focused, Stremio sources present: badge focus.
2. Non-live context and focus in the dock while not scrubbing: cinemaProgressContainer, or badge focus.
3. Live IPTV:
   - First press: arms iptvUpPressActive.
   - repeat≥3: hideControlsMenu + showIptvChannelJumpDialog@11816.
   - ACTION_UP without a long press: showIptvGuide (O).
   - Always consumed.
4. Stremio TV with channels: showStremioTvGuide@19543.
5. playlistMode NONE: super.
6. Otherwise showPlaylist (H).

### Outgoing calls to functions outside the chunk, by cluster
- **A:** zapIptvChannel@12549, hideIptvEpgPane@11293, isFocusInIptvEpgPanel@11539, focusedIptvGuideEntry@11140, showIptvSchedulePane@11153, hideStremioTvGuide@19568, isFocusInStremioTvGuideList@19648, showIptvChannelJumpDialog@11816, showStremioTvGuide@19543, isLiveIptvZapContext@12522.
- **B:** restoreParkedIptvTwinIfNeeded@630, showIptvZapBanner@13587, hideIptvZapBanner@13731, updateOttIdentity@5641, hideStremioSourceBadgeImmediately@18905, showStremioSourceBadge@18866, hideStremioSourceBadge@18888, refreshOttCaptionFor@4250.
- **C:** formatTime@17163.
- **D:** setOttTrackHeight@4212, releaseResumeHold@1408, formatTime.
- **E:** releaseResumeHold, formatTime.
- **F:** releaseResumeHold, TvSkipSegmentClients (external object).
- **G:** sendProgress@16801.
- **H:** seedGuideSkinChrome@3498, selectSeasonTab@3747, selectMovieTab@4120.
- **J:** canShuffleWholeShow@5461, pickShuffleIndex@5574, playItem@4556.
- **K:** bindViews, setupPlayer, setupSeekbar, setupControls, setIptvPreferredAudioLang@14240, updateIptvEpisodeControls@14213, setupBackPressHandler, setupMetadataReceiver, playIptvChannel@14170, bootstrapInitialIptvZapPaging@11749.
- **L:** dp@6644, guideTypeface@12802, updateIptvStartOverButton@11329, updateIptvStartOverSeekButton@11350.
- **M:** none in the activity; it uses only singletons and services.
- **N:** requestIptvBrowse@10912, disableIptvZapPaging@12247, switchToIptvChannel@12340, beginIptvCategoryZapSession@11682, showIptvListPicker@10682, toggleIptvFavorite@11008, ensureIptvChannelEpg@11049, prefetchIptvZapPage@12190, requestIptvCatchup@11401, selectIptvEpgDay@11245, updateIptvGuideCurrentName@11619, dp, guideTypeface.
- **O:** trimHiddenIptvZapWindow@12180, hideIptvEpgPane, hideIptvZapBanner, updateIptvGuideCurrentName, bootstrapInitialIptvZapPaging, requestIptvBrowse, dp.

### Intra-chunk edges
- A calls B, D, E, H, J and O.
- B calls hideIptvZapBanner, which belongs to the zap banner outside the chunk.
- C calls F every 100 ms.
- F reads J (upNextVisible) and B/E/H visibility.
- J reads B, E, H, I and O visibility; it calls H (getNextPlayableIndex).
- K calls L, N and B (via the "Guide" button). The playlist button click calls hideControlsMenu + toggleIptvGuide (8905–8908).
- L calls M (updateRecordButtonState) and O (hideIptvGuide), and writes D state.
- N calls O and M (promptScheduleRecording).
- O calls nothing in L.

---------------------------------------------------------------------------
## 4. Extraction candidates, low to high risk

1. **Recording URL policy** (M pure part: isSegmentedStreamUrl, xtreamTsTwin, engineRecordableUrl(url, hlsForced), isSchedulableStreamUrl, sanitizeRecordingName, recordingTimestamp).
   - Pure functions, so they can become a top-level `object IptvRecordingUrlPolicy` with plain JVM tests and no host interface.
   - Risk: lowest. Preserve the regex text exactly.
2. **IPTV payload parsing** (K parsers 8919–9096).
   - Pure apart from the private data-class types (IptvChannelEntry@21413, IptvSourceEntry@21790, IptvListEntry@21805).
   - The data classes are file-private, so they must become `internal` in the same move.
   - Behaviour to keep:
     - User-Agent key normalisation.
     - `contentType` defaults to "live" when duration is -1.
     - `isContinue` sources are filtered out.
     - The two overloads differ on season/episode: the JSONArray overload treats -1 as null, while the List overload passes raw values.
3. **Playlist navigation policy** (getNextPlayableIndex, getPrevPlayableIndex, computeMovieGroups).
   - Pure given (payload, playlistMode, movieGroups). Move them to a `PlaylistNavigator` taking those as parameters.
   - Watch the payload read inside computeMovieGroups at 8561.
   - Low risk, high test value.
4. **Sleep timer** (G).
   - A `SleepTimerController(handler, clock)` with callbacks: onFire → host sendProgress(false) then pause(); then releaseScreen(); toast(text).
   - sleepStopLatched is shared: B resets it (7417) and playbackListener sets it (1682, 1717). The controller must own it with an explicit API (latch/clear).
   - Low-to-medium risk.
5. **Skip-segment controller** (F).
   - Already self-contained state and an owned scope; it can mirror SubtitlePanelController.
   - Host interface: `player position/duration`, `hasEverBeenReady`, `isIptvMode`, `payload/currentIndex` (or a request supplier), `isUpNextVisible`, `controlsMenuVisible`, `canOfferFocus()` (aggregates the overlay states), `releaseResumeHold()`, `seekTo`, `showSeekForward`, `requestPlayerFocus`.
   - Must keep the generation/key staleness guard and the cancel in onDestroy@19370–19372.
   - Medium risk.
6. **Up Next card** (J) plus the next overlay (I).
   - Host interface: `isCleanPlaybackState()` (reads about 12 flags across clusters), `nextIndex()` (shuffle or linear), `playItem(index, autoAdvance=true)`, `currentIndex`, `payload items`, Glide load.
   - The ticker and the hide-in-playItem contract (4611) must stay.
   - Medium risk.
7. **IPTV recording actions** (M stateful part).
   - Host interface: currentStreamUrl, currentHeaders, currentEntry, sources, hlsForcedUrls, `requestPermissions(code)`, `showDialog`, toast.
   - The registry listener add/remove ordering in onCreate@2038 / onDestroy@19315 must move with it.
   - Medium risk: profile authorisation and foreground-service start.
8. **Cinema scrub + progress ticker** (C+D, plus E's seekBy).
   - Shared mutable seekbarPosition/videoDuration/currentSeekSpeed with the dead legacy E, plus direct writes from L (9717–9720).
   - Needs an explicit `resetForLive()` API. The host must supply ottSkinInstalled, setOttTrackHeight, releaseResumeHold and the skip-segment tick.
   - Medium-high risk.
   - Delete legacy E only as a separate, evidenced removal: showSeekbar has no callers. Even then, setupSeekbar@3135 still references hideSeekbar.
9. **IPTV guide (N+O)** and **live dock skin (L)**.
   - They share about 25 zap/browse tokens and windows with the out-of-chunk zap pager (11682–12600) and browse bridge (10912).
   - Extracting O alone would need a host exposing every token bump and the zap-window state. Do this only together with the zap/browse cluster (another chunk).
   - High risk.
10. **Key dispatcher (A)** and **controls overlay (B)**.
    - A reads visibility from every cluster, so it should be extracted last, as a `TvKeyRouter` over a host interface of about 15 predicates and actions.
    - Branch order is behaviour: A8 falls through, A6 consumes all keys, and repeat-count gates apply.
    - B is called from about 30 external sites (hideControlsMenu has 17 external references).
    - Highest risk.

---------------------------------------------------------------------------
## 5. Lifecycle and teardown ordering facts

- **onCreate:**
  - `RecordingRegistry.addListener(recordingRegistryListener)` at 2038, before the `mode=="iptv"` branch at 2097–2099, which calls initIptvMode and returns.
  - The listener guards with `!isDestroyed && !isFinishing` (9255).
- **onStop@19122:** cancelPendingIptvCatchupRequest at 19126, then finalizeIptvRecordingIfActive at 19141 (tee only; engine captures survive by design), then iptvLiveRecovery.cancel.
- **setupBackPressHandler@19161:** hides overlays in order — linePicker/sync, then hideIptvGuide at 19175, then hidePlaylist at 19181.
- **onDestroy@19270:**
  - Order: removeListener(recordingRegistryListener) 19315, then cancelSleepTimer 19318, then finalizeIptvRecordingIfActive 19322, then iptvBrowseHandler.removeCallbacksAndMessages 19329, then upNextHandler.removeCallbacksAndMessages 19350, then skipSegmentFetchJob.cancel 19370 + skipSegmentScope.cancel 19372, then progressHandler / controlsHandler / seekbarHandler removeCallbacksAndMessages 19376–19378, then player.release at 19393.
  - Handler and coroutine teardown precedes player release. C, F and J callbacks touch `player`.
- **Not cancelled in onDestroy:** cinemaProgressAnimator (cancelled only in exitCinemaSeekMode and updateCinemaProgressUI), view ViewPropertyAnimators with withEndAction, View.post/postDelayed focus lambdas (playlistView 8444, iptvGuideList 10207), and AlertDialogs from O and M. An extraction must not silently add or drop any of these cancellations.
- **Per-item reset in playItem@4556:**
  - hasEverBeenReady=false, maxStableDurationMs=0 and lastRealPositionMs=0 (4607–4609), then hideUpNextCard (4611), then resetSkipSegmentState (4612).
  - F depends on hasEverBeenReady=false hiding the button until the new media is ready (8175).
- **Sleep fire ordering:** fireSleepTimer runs cancelSleepTimer, sets sleepStopLatched=true, calls sendProgress(false) **before** pause, then releases the screen. holdScreenForPlayback re-arms on onIsPlayingChanged(true) at 1805.
- **Controls auto-hide:** hideControlsRunnable re-schedules if focus is still in the overlay. scheduleHideControlsMenu posts only while `isPlaying`. showControlsMenu always cancels first.
- **Cinema scrub:** enter pauses only when playWhenReady was true; exit resumes only then. L's live reset clears cinemaSeekWasPlaying without resuming.
- **IPTV guide hide:** trimHiddenIptvZapWindow is deliberately posted (10222), because hide can run inside a row's click dispatch. Keep the deferral.
- **Skip-segment fetch:** the result is rejected unless both the generation (8240) and the recomputed request key (8242) still match.

---------------------------------------------------------------------------
## 6. Existing JVM tests touching this chunk, and gaps

android/app/src/test has about 40 files. None names a function from this chunk.
- **Indirect coverage:**
  - StremioTvStartupWatchdogTest injects `nextOverlay`, `isIptvMode` and `titleView` by reflection (54, 70). It drives `playbackListener` STATE_ENDED (117, 138), which can reach showNextOverlay, getNextPlayableIndex or the sleep END_OF_ITEM branch. Coverage is incidental; nothing is asserted about them.
  - SubtitleSyncDismissTest@59–81 invokes `setupBackPressHandler`, whose callback reaches hideIptvGuide and hidePlaylist, but asserts only overlay dismissal.
  - SubtitleControlsLiftControllerTest covers the lift controller that B drives, not B's calls into it.
  - TvControlsSkinTest covers skin specs (dockSkinSpec), not updatePauseButtonLabel.
  - ShufflePlaybackFlowTest covers shuffle state, not maybeShowUpNext.
- **Gaps:**
  - Pure-JVM tests could cover candidates 1–3 after extraction, but they need a characterization pass first. Robolectric reflection on the activity is the existing house pattern (`Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java).get()` plus a field helper).
  - dispatchKeyEvent routing table A1–A15: the order of precedence, A8 fall-through, the repeat-count gates (CH zap first press only, long-press threshold 3), and the live-IPTV UP press/long-press/ACTION_UP guide state machine.
  - togglePlayPause dead-live path (userRetry versus play) and the sleepStopLatched reset.
  - Skip segments: the hasEverBeenReady gate, a stale generation/key rejecting a result, cache eviction at 64, focus offered once per key, suppression while upNextVisible.
  - Up Next: threshold and minimum duration, the upNextDismissedForIndex latch, the ticker hiding when not clean or on a seek back, and the trigger at ≤ TICK+250 ms.
  - Sleep timer: countdown fire order (sendProgress before pause), END_OF_ITEM, and screen flags.
  - Cinema scrub: pause/resume intent, the live reset from L, and the OTT preview chip.
  - Recording: engine versus tee gating, Xtream twin, schedule gating, the notification permission asked once, and profile authorization refusal.
  - IPTV search context: begin, restore and commit token bumps and saved-window restore. Category picker filtering.
  - initIptvMode parsing round-trip (both overloads) and the start index clamp.
  - Dead code to record in the plan: showSeekbar, stopSeekbarProgressUpdates, and the dispatcher seekbar branch A6.

---

## AndroidTvTorrentPlayerActivity.kt — responsibility map, chunk D (lines 10600–14760)

File: `android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt` (revision: refactor/codebase @ 39c630303).
Chunk starts at the tail of the category-picker dialog (10593–10600 belongs to the previous function) and ends at 14757
(14759+ is "Track selection / UNIFIED MENU backing", not in this chunk).

Supporting types (outside chunk, all `private` top-level in the same file — extraction to another file requires
widening to `internal`): `StremioSource`@20230, `IptvChannelEntry`@21413 (mutable data class: `index`, `isCurrent`,
`isFavorite`, `epg*` fields, `resumePositionMs`), `IptvChannelAdapter`@21472, `IptvSourceEntry`@21790,
`IptvListEntry`@21805, `IptvEpgProgram`@21811, `IptvEpgAdapter`@21819. Style types live in `IptvGuideStyle.kt`
(`GuideStyle`, `GuideTokens`) and `TvControlsSkin.kt`.

Shared IPTV state almost every cluster touches (declared in the activity field block):
`isIptvMode`@862, `iptvChannels`@863, `currentIptvIndex`@864, `iptvChannelAdapter`@1007, `iptvGuideVisible`@1008,
`iptvBrowseHandler`@1022, `progressHandler`@1363, `player`@262, `titleView`@143, `controlsMenuVisible`@835.

---

## 1. Responsibility clusters

### C1 — Guide list adapters (nested static classes) — 10602–10672, 10837–10909
- `IptvCategoryAdapter`@10602 (ctor: selectedCategory, searchViewId, tokens, rowRadiusPx, onSelected; `update`@10667).
- `IptvListPickerAdapter`@10837 (ctor: lists, membership Set, tokens, rowRadiusPx, onToggle; `setReady`@10848;
  `getItemCount` returns 0 until ready @10908).
- Own only their own fields; no activity state (they are `private class`, not `inner`). Pure view code.
- External caller: `IptvCategoryAdapter` constructed @10495 (category dialog, outside chunk).

### C2 — Channel list membership / favourites — 10682–10835, 11008–11041
- `showIptvListPicker`@10682, `removeIptvGuideRow`@10825, `toggleIptvFavorite`@11008.
- Owns no fields. Reads: `guideTokens`@12706 (C9), `iptvLists`@1014, `iptvSources`@1010, `iptvSourceId`@1016,
  `iptvAllCategorySearchActive`@1041. Writes: `entry.isFavorite`, `iptvBrowseChannels`@1009,
  `iptvSearchSavedChannels`@1043 (removeAll), adapter notify.
- External callers: `showIptvListPicker`@9855, `toggleIptvFavorite`@9857 (guide long-click wiring).

### C3 — Guide browse request — 10912–11006
- `requestIptvBrowse`@10912.
- Writes C6 zap-context fields: `iptvUiContextToken`@1036 (++), `iptvZapOwnsUiContext`@1037=false,
  `iptvZapRequestToken`@1031 (++), `iptvZapRequestInFlight`@1032=false, `iptvZapPendingInputs`@1033.clear().
- Owns/writes: `iptvBrowseToken`@1020, `iptvBrowseLoading`@1000, `iptvGuideUsesZapWindow`@1035,
  `iptvBrowseChannels`@1009, `iptvSourceId/Name/ContentType/SelectedCategory`@1016–1019, `iptvCategories`@1015.
- Reads: `iptvGuideSearch`@995, `iptvGuideList`@994, `iptvChannels`, `currentIptvIndex`, `iptvGuideVisible`.
- Stale guard: token + uiContext + `!iptvZapOwnsUiContext` on success/error/notImplemented.
- External callers: 9830, 9974, 9989, 10379, 10401, 10506.

### C4 — EPG now/next + schedule pane — 11043–11306, 11539–11675, 14136–14148
- `ensureIptvChannelEpg`@11049, `updateIptvGuideEpgHeader`@11125, `focusedIptvGuideEntry`@11140,
  `formatEpgTime`@11149, `showIptvSchedulePane`@11153, `paintIptvEpgLogo`@11204, `selectIptvEpgDay`@11245,
  `hideIptvEpgPane`@11293, `isFocusInIptvEpgPanel`@11539, `requestIptvEpg`@11557 (bridge + 45 s watchdog),
  `updateIptvGuideCurrentName`@11619, `adoptIptvEpg`@14136.
- Owns: `iptvEpgPanel`@1057, `iptvEpgLogo`@1058, `iptvEpgLetter`@1059, `iptvEpgChannelName`@1060,
  `iptvEpgChannelGroup`@1061, `iptvEpgDate`@1062, `iptvEpgLoading`@1063, `iptvEpgEmpty`@1064, `iptvEpgList`@1065,
  `iptvEpgAdapter`@1066, `iptvEpgPrograms`@1067, `iptvEpgDayOffset`@1068, `iptvEpgToken`@1069,
  `iptvEpgVisible`@1070, `iptvEpgEntry`@1071; guide header views `iptvGuideCurrentName`@1001,
  `iptvGuideCurrentGroup`@1002, `iptvGuideCurrentEpg`@1003, `iptvGuideNowPlaying`@1004, `iptvGuideNowLogo`@1005,
  `iptvGuideNowLetter`@1006. Per-entry EPG state lives on `IptvChannelEntry` (epgLoading/epgLoaded/epgNow*/epgNext*/
  epgCatchupMetadataLoaded).
- Reads other clusters: `iptvZapBanner`@12662 (C8) in `ensureIptvChannelEpg`@11113 → calls C8 `paintIptvZapBannerEpg`;
  calls C5 `updateIptvStartOverButton`@11111; `iptvGuideVisible`, `iptvChannels`, `currentIptvIndex`.
- `selectIptvEpgDay` does `findViewById` for 6 day buttons on every call (11270–11277).
- External callers: `ensureIptvChannelEpg`@9860 (row bind), `focusedIptvGuideEntry`@7109, `showIptvSchedulePane`@7110,
  `selectIptvEpgDay`@10014–10029, `hideIptvEpgPane`@7082,7092,10199,10223, `isFocusInIptvEpgPanel`@7090,
  `updateIptvGuideCurrentName`@10033,10201,10285.

### C5 — Start Over / catch-up — 11308–11537
- `currentIptvStartOverProgramme`@11308 (pure over entry + clock), `updateIptvStartOverButton`@11329,
  `updateIptvStartOverSeekButton`@11350, `showIptvStartOverTimeline`@11362, `toggleIptvStartOver`@11378,
  `cancelPendingIptvCatchupRequest`@11394, `requestIptvCatchup`@11401.
- Owns: `iptvStartOverButton`@193, `iptvStartOverSeekButton`@194, `iptvStartOverActive`@865,
  `iptvStartOverLoading`@866, `iptvStartOverTimelineVisible`@867, `iptvCatchupToken`@868.
- Reads/writes others: `iptvEpgToken` (C4, relevance check), `iptvGuideVisible`; on VOD replay rewrites
  `iptvChannels`, `currentIptvIndex`, `iptvSeriesAudioKey`@875 (11498–11501); `player.duration`.
- Calls out: `updateIptvControlPresentation`@9678, `resetSubtitleState`@4797, `showControlsAndFocusProgressBar`@7725,
  `commitIptvAllCategorySearch`@10294, `hideIptvGuide`@10214; in-chunk: `beginIptvPlayback`, `switchToIptvChannel`,
  `setIptvMediaItem`, `checkpointCurrentIptvPosition`, `updateIptvEpisodeControls`.
- External callers: `toggleIptvStartOver`@4442, `showIptvStartOverTimeline`@4447, `updateIptvStartOverButton`@9701,
  `updateIptvStartOverSeekButton`@9702, `requestIptvCatchup`@9897, `cancelPendingIptvCatchupRequest`@1875,19126,19271.
- Note: `switchToIptvChannel`@12346–12349 also resets all four start-over fields (C7 writes C5 state).

### C6 — Zap paging engine (category window, CH+/−, jump, boundary cache) — 11677–12338, 12517–12650
- `beginIptvCategoryZapSession`@11682, `bootstrapInitialIptvZapPaging`@11749, `restoreIptvZapBootstrapFallback`@11787,
  `showIptvChannelJumpDialog`@11816, `requestIptvChannelJump`@11870, `requestIptvZapPage`@11977,
  `installIptvZapWindow`@12088, `mergeIptvZapPage`@12136, `boundedHiddenIptvZapWindow`@12170,
  `trimHiddenIptvZapWindow`@12180, `prefetchIptvZapPage`@12190, `queuePendingIptvZapInput`@12215,
  `drainPendingIptvZapInputs`@12221, `clearIptvZapBoundaryCache`@12235, `disableIptvZapPaging`@12247,
  `adjacentIptvCategory`@12255 (pure), `prefetchAdjacentIptvCategory`@12267, `consumeCachedAdjacentIptvCategory`@12308,
  `isLiveIptvZapContext`@12522, `activateIptvZapUiContext`@12527, `zapIptvChannel`@12549,
  `requestAdjacentIptvCategory`@12586.
- Owns: `iptvZapPageSize`@1023 (const-like), `iptvZapPagingActive`@1024, `iptvZapCategory`@1025,
  `iptvZapSourceId`@1026, `iptvZapSourceName`@1027, `iptvZapContentType`@1028, `iptvZapCategories`@1029,
  `iptvZapCategoryTotal`@1030, `iptvZapRequestToken`@1031, `iptvZapRequestInFlight`@1032,
  `iptvZapPendingInputs`@1033 (cap 24 @12216), `iptvZapDrainingInputs`@1034, `iptvGuideUsesZapWindow`@1035,
  `iptvUiContextToken`@1036, `iptvZapOwnsUiContext`@1037, `iptvZapMaxHiddenWindow`@1047,
  `iptvZapCached*`@1048–1054.
- Writes shared/guide state: `iptvChannels`, `currentIptvIndex`, `iptvBrowseChannels`, `iptvBrowseToken` (C3),
  `iptvSourceId/Name/ContentType/SelectedCategory`, `iptvCategories`, `iptvGuideSearch.setText("")`, entry `index`/`isCurrent`.
- Reads: `iptvSources` (jump/favourites gate), `iptvGuideVisible` (hidden-window bound), `controlsMenuVisible`.
- Calls out: `commitIptvAllCategorySearch`@10294, `refreshIptvBrowserChrome`@10323, `parseIptvChannels`@9004,
  `iptvChannelAdapter.entriesSnapshot/updateChannels`; in-chunk: C7 `switchToIptvChannel`, C4
  `updateIptvGuideCurrentName`, C8 `refreshIptvZapBannerPosition`, C10 `checkpointCurrentIptvPosition`,
  `updateIptvEpisodeControls`.
- External callers: `beginIptvCategoryZapSession`@9844, `bootstrapInitialIptvZapPaging`@8915,10288,
  `showIptvChannelJumpDialog`@4436,7301, `trimHiddenIptvZapWindow`@10222, `prefetchIptvZapPage`@9886,9887,
  `disableIptvZapPaging`@9839, `isLiveIptvZapContext`@7340,7361, `zapIptvChannel`@7071,7342,7363,9123,9130.
- Recursion/re-entrancy: `drainPendingIptvZapInputs` → `zapIptvChannel` → `prefetch*` → `requestIptvZapPage`;
  guarded by `iptvZapDrainingInputs` and early break on `iptvZapRequestInFlight` (12228).
  `bootstrapInitialIptvZapPaging` recurses for the newly-playing entry (12764).

### C7 — Channel switch + watch registration + startup-channel memory — 12340–12515
- `switchToIptvChannel`@12340, `noteLiveChannelPlaying`@12429, `beginIptvPlaybackAfterWatchRegistration`@12468.
- Owns: `lastLiveChannelSettleMs`@12424 (val 1000), `lastLiveChannelArmedUrl`@12426, `lastLiveChannelRunnable`@12427
  (declared inside the chunk, not in the field block); `iptvWatchRegistrationToken`@1021.
- Writes: C5 start-over fields + `iptvCatchupToken`; `iptvChannels`, `currentIptvIndex`, `iptvSeriesAudioKey`@875,
  `titleView.text`.
- Calls out: `dropStaleSourceSwitchFeedback`@17896, `resetSubtitleState`@4797; in-chunk: `checkpointCurrentIptvPosition`,
  `beginIptvPlayback` (C11), `showIptvZapBanner`/`hideIptvZapBanner` (C8), `updateIptvGuideCurrentName` (C4),
  `updateIptvEpisodeControls` (C10).
- External callers: `switchToIptvChannel`@1733,4500,4510,9840; `noteLiveChannelPlaying`@1809 (player listener).

### C8 — Zap banner (classic + styled trees) — 12652–12693, 12815–12876, 12877–13079, 13081–14124
- `isRecordingCurrentIptvChannel`@12818, `zapText`@12822, `zapHint`@12841, `ensureIptvZapBanner`@12877,
  `styledZapText`@13097, `styledZapHint`@13122, `buildStyledIptvZapBanner`@13158, `showIptvZapBanner`@13587,
  `applyIptvZapBannerMode`@13673, `scheduleIptvZapBannerTick`@13716, `hideIptvZapBanner`@13731,
  `applyStyledZapBannerMode`@13745, `paintIptvZapBannerIdentity`@13812, `paintIptvZapBannerPosition`@13877,
  `paintStyledZapBannerIdentity`@13910, `paintStyledZapBannerEpg`@13972, `paintIptvZapBannerEpg`@14046,
  `formatIptvRemaining`@14101 (pure), `refreshIptvZapBannerPosition`@14112.
- Owns (declared in chunk): `iptvZapBanner`..`iptvZapBannerRail`@12662–12675, `iptvZapBannerDocked`@12681,
  `iptvDockLayoutListenerAttached`@12682, `iptvZapBannerLayoutListenerAttached`@12683, `iptvZapBannerEntry`@12688,
  `iptvZapBannerHideToken`@12689, `iptvZapBannerTickToken`@12690, `iptvZapAccent`@12692,
  `iptvZapStyledScrim/Card/GlassCardWidth/Rule/Live/Rec/End/MeterRow`@13088–13095.
- Reads: `guideTokens`/`guideStyle`/`guideTypeface` (C9), `controlsMenuVisible`@835, `controlsOverlay`@187,
  `iptvGuideVisible`, `iptvZapPagingActive`/`iptvZapCategoryTotal`/`iptvZapSourceId` (C6), `iptvSources`,
  `iptvChannels`, `currentIptvIndex`, `recordingEngineEnabled`@9244, `iptvRecordingController`@197; calls C4
  `ensureIptvChannelEpg`, `formatEpgTime`, `adoptIptvEpg`; `engineTaskIdForCurrentChannel`@9329,
  `updateSubtitleControlsLift`@7589, `dp`@6644.
- External callers/readers: `showIptvZapBanner`@7456, `hideIptvZapBanner`@7458,7540,10192, `iptvZapBannerDocked`
  read @7540,7593,7599, `iptvZapBanner` read @7592,7598 (subtitle-lift code).

### C9 — Style/skin configuration (read-once lazies) — 12694–12813
- `guideStyle`@12698 (lazy, pref `iptv_player_guide_style`), `guideTokens`@12706, `controlsSkin`@12713
  (pref `TvControlsSkin.PREF_KEY`, default "ott"), `DockSkinSpec`@12727, `dockSkinSpec`@12742, `guideTypefaces`@12800,
  `guideTypeface`@12802.
- Reads `playerPreferences`@2012 (lateinit `NativePlayerPreferences`), `assets`.
- Not IPTV-specific: `controlsSkin`/`dockSkinSpec` drive the whole controls dock — external readers
  3174–3512, 4145–4355, 5658–5838, 7632, 16601; `guideTokens`/`guideStyle`/`guideTypeface` read at 9169–10427.

### C10 — VOD position + episode navigation + series audio — 14150–14274
- `checkpointCurrentIptvPosition`@14158, `playIptvChannel`@14170, `isIptvEpisodeMode`@14195, `nextIptvEpisode`@14201,
  `prevIptvEpisode`@14206, `updateIptvEpisodeControls`@14213, `setIptvPreferredAudioLang`@14240,
  `onIptvSeriesAudioPicked`@14254, `languageOfOverride`@14266 (pure).
- Owns: `iptvSeriesAudioKey`@875 (shared with C5/C7), `iptvPreferredAudioLang`@876; buttons `iptvPrevButton`@189,
  `iptvNextButton`@190.
- Reads: `player.duration/currentPosition`, `trackSelector`@264, `iptvZapPagingActive` (C6).
- External callers: `playIptvChannel`@8914, `nextIptvEpisode`@1733,4499, `prevIptvEpisode`@4510,
  `updateIptvEpisodeControls`@8863, `setIptvPreferredAudioLang`@8860, `onIptvSeriesAudioPicked`/`languageOfOverride`@14920,15658.

### C11 — Tune pipeline (media item, HLS fallback, decoder error) — 14276–14534
- `isStremioIptvUrl`@14278, `IptvStremioCandidate`@14281, `setIptvMediaItem`@14284, `reportDecoderFailure`@14411
  (not IPTV-specific; KDoc above it @14389–14397 actually documents `retryIptvAsHlsIfUnrecognized`),
  `retryIptvAsHlsIfUnrecognized`@14431, `beginIptvPlayback`@14479.
- Writes: `currentIptvHttpHeaders`@883, `currentIptvStreamUrl`@992, `iptvStrictTsActive`@901, `iptvHlsForcedUrls`@888,
  `iptvLiveRecovery.expectRetune`; reads `iptvStartsWithStrictTs`@906, `iptvStrictTsUrls`@897,
  `iptvTwinTrialUrl`@936, `iptvTwinTrialRestoreOriginal/Twin`@955/959, `iptvTwinPreferredUrls`@944,
  `iptvLiveRetuneInFlight`@354, `subtitleTrackReadiness`@1230, `playerView`@139.
- Calls out: `finalizeIptvRecordingIfActive`@9654, `clearIptvTwinTrial`@650, `clearParkedIptvTwinRestore`@641,
  `iptvTuneDiagnostics.onTuneStart/note`@344, `iptvLiveRecovery.onTuneStarted`@369, `hideIptvReconnectPill`@777,
  `restartProgressUpdates`@16651, `updateRecordButtonState`@9357, `iptvRecordingController.abortAndDelete`.
- External callers: `setIptvMediaItem` @483,504,571,637,676 (twin trial / restore / live recovery; other textual
  hits 352–934 and 19106/19124 are comments), `beginIptvPlayback`@1881, `retryIptvAsHlsIfUnrecognized`@1872,1911,
  `reportDecoderFailure`@1939,1949.

### C12 — Stremio-addon IPTV candidate ladder — 14536–14757
- `populateIptvStremioSources`@14542, `iptvQualityFromLabel`@14563 (pure), `clearIptvStremioSources`@14575,
  `switchToIptvStremioSource`@14588, `tryNextIptvStremioCandidate`@14613, `armIptvStremioStallWatchdog`@14660,
  `cancelIptvStremioStallWatchdog`@14678, `reportIptvStremioWinnerIfNeeded`@14684, `requestIptvStreamUrls`@14698,
  `reportIptvStreamResult`@14746. (beginIptvPlayback@14479 initialises this cluster's state.)
- Owns: `iptvStremioToken`@1078, `iptvStremioChannelKey`@1079, `iptvStremioCandidates`@1080,
  `iptvStremioCandidateIndex`@1081, `iptvStremioWinnerReported`@1082, `iptvStremioStallRunnable`@1086.
- Writes movie-source state: `stremioSources`@1089, `currentStremioSourceIndex`@1090, `stremioSourceBadge`@1091;
  calls `setupStremioSources`@17814, `updateStremioQualityBadge`@17832, `sourceBrowser.render()`@1201,
  `watchSourceSwitchOutcome`@17846, `dropStaleSourceSwitchFeedback`@17896.
- External callers: `switchToIptvStremioSource`@18757, `tryNextIptvStremioCandidate`@1930,
  `reportIptvStremioWinnerIfNeeded`@1523.

---

## 2. External effects per cluster

| Cluster | MethodChannel (`MainActivity.getAndroidTvPlayerChannel()`) | Handlers / timers | Views / focus / other |
|---|---|---|---|
| C1 | — | — | creates TextViews; `animate()` scale 120 ms on focus |
| C2 | `setIptvChannelInList` (fire-and-forget), `getIptvChannelListMembership` (Result), `setIptvFavorite`; falls back to `toggleIptvFavorite` when channel null | `listView.post` focus | AlertDialog (`Theme_Debrify_SubtitleDialog`), Toasts |
| C3 | `requestIptvBrowse` (Result) | `iptvGuideSearch.post`, `iptvGuideList.post` focus | Toast on error |
| C4 | `requestIptvEpg` (Result) | `iptvBrowseHandler.postDelayed` 60 s archive-metadata retry (11080); local `Handler(mainLooper)` 45 s watchdog + `post` for null delivery (11576–11615) | Glide into `iptvEpgLogo` / `iptvGuideNowLogo` (`iptvGuideNowLogo!!` @11666); `findViewById` day buttons; `iptvEpgList.post` focus; `DateFormat`/`SimpleDateFormat` with default locale |
| C5 | `requestIptvCatchup` (Result) | — | Toasts (hardcoded English); `player.duration`; focus `iptvStartOverSeekButton` |
| C6 | `requestIptvBrowse` with action `channelNumber` / `zapPage` (Result) | — | jump AlertDialog + EditText (IME ALWAYS_VISIBLE); Toasts |
| C7 | `noteIptvLiveChannel` (fire-and-forget), `recordIptvWatch` (Result) | `iptvBrowseHandler.postDelayed` settle 1 s (12465) and 2 s registration fallback (12492) | `titleView.text`; `player.isPlaying` |
| C8 | — | `progressHandler.postAtTime` hide (token, 4.5 s) and tick (token, 1 s, self-rescheduling) | builds view trees, `addView` to `android.R.id.content`; two `addOnLayoutChangeListener` (banner, `controlsOverlay`), never removed; Glide clear/load; `animate()` alpha/translation |
| C9 | — | — | `NativePlayerPreferences.getString`; `Typeface.createFromAsset(flutter_assets/assets/fonts/…)` memoized |
| C10 | `saveIptvSeriesAudio` (fire-and-forget) | — | `trackSelector.parameters` (Media3 preferred audio languages via `LanguageMapper`) |
| C11 | — | — | Media3: `setMediaItem(item[,startAt])`, `prepare`, `playWhenReady`, `play`, `stop`; `MimeTypes.APPLICATION_M3U8`; `playerView.setKeepContentOnPlayerReset(true)`; Toasts |
| C12 | `requestIptvStreamUrls` (Result, delivered via `runOnUiThread` in caller), `reportIptvStreamResult` (fire-and-forget) | `progressHandler.postDelayed` 20 s stall watchdog | Media3 `setMediaItem/prepare/play` in manual-pick fallback; Toasts |

No broadcasts, no direct network, no coroutines in this chunk. No SharedPreferences writes (only C9 reads).

---

## 3. Coupling (in-chunk cluster graph + outgoing calls)

- C3 → C6 state (resets zap tokens/inputs). C6 → C3 state (`iptvBrowseToken++` @11696, 12530).
- C4 → C5 (`updateIptvStartOverButton`), C4 → C8 (`paintIptvZapBannerEpg` when banner visible).
- C5 → C7 (`switchToIptvChannel`), C11 (`setIptvMediaItem`, `beginIptvPlayback`), C10 (`checkpointCurrentIptvPosition`,
  `updateIptvEpisodeControls`); reads C4 `iptvEpgToken`.
- C6 → C7, C4 (`updateIptvGuideCurrentName`), C8 (`refreshIptvZapBannerPosition`), C10.
- C7 → C10, C11 (`beginIptvPlayback`), C8 (show/hide), C4; writes C5 fields.
- C8 → C4 (`ensureIptvChannelEpg`, `formatEpgTime`, `adoptIptvEpg`), C9, C6 state reads.
- C10 → C11 (`playIptvChannel` → `beginIptvPlayback`), C8 (`showIptvZapBanner`).
- C11 ↔ C12 (`beginIptvPlayback` resets ladder; `retryIptvAsHlsIfUnrecognized` re-arms watchdog; C12 calls `setIptvMediaItem`).
- Outgoing (outside chunk): `dp`, `parseIptvChannels`, `refreshIptvBrowserChrome`, `commitIptvAllCategorySearch`,
  `hideIptvGuide`, `updateIptvControlPresentation`, `resetSubtitleState`, `showControlsAndFocusProgressBar`,
  `dropStaleSourceSwitchFeedback`, `finalizeIptvRecordingIfActive`, `clearIptvTwinTrial`, `clearParkedIptvTwinRestore`,
  `hideIptvReconnectPill`, `restartProgressUpdates`, `updateRecordButtonState`, `engineTaskIdForCurrentChannel`,
  `updateSubtitleControlsLift`, `setupStremioSources`, `updateStremioQualityBadge`, `watchSourceSwitchOutcome`,
  `iptvTuneDiagnostics`, `iptvLiveRecovery`, `iptvRecordingController`, `subtitleTrackReadiness`, `sourceBrowser`.

---

## 4. Extraction candidates (low → high risk)

1. **Pure helpers** — `formatIptvRemaining`@14101, `iptvQualityFromLabel`@14563, `adjacentIptvCategory` math @12255
   (take categories/current/delta/attempt), `currentIptvStartOverProgramme`@11308 (take entry + nowMs),
   `boundedHiddenIptvZapWindow` @12170 (take list, guideVisible, max), `languageOfOverride`@14266, `isStremioIptvUrl`.
   No host needed; plain JVM unit tests. Needs `IptvChannelEntry`/`IptvEpgProgram` widened to `internal`.
2. **C1 adapters** → own file(s) (`IptvCategoryAdapter`, `IptvListPickerAdapter`). Already static; only depend on
   `GuideTokens`, `R`. No host interface.
3. **C9 style config** → `TvPlayerStyleConfig(prefs, assets)` holding `guideStyle`, `guideTokens`, `controlsSkin`,
   `dockSkinSpec`, `guideTypeface`. Must stay lazy: `playerPreferences` is `lateinit` (@2012) and `controlsSkin` is
   evaluated at `setupControls` time. Many external readers (dock code) — mechanical rename only.
4. **C8 zap banner** → `IptvZapBannerController(activity/root, styleConfig, progressHandler, callbacks)`. Self-contained
   view ownership; Callbacks: `isControlsMenuVisible()`, `isGuideVisible()`, `controlsOverlay(): View?`,
   `zapPosition(): {pagingActive, categoryTotal, channelCount}`, `activeSourceIsFavorites()`, `playingEntry()`,
   `ensureEpg(entry)`, `isRecordingCurrentChannel()`, `onDockedLayoutChanged()` (→ `updateSubtitleControlsLift`).
   Must expose `isVisible`, `isDocked`, `view` for 7540/7592–7599. Risk: ~1,450 lines of view building (the styled
   builder alone 13158–13577 is >400 lines — likely needs its own classic/styled split to meet the 800-line rule);
   tokens on shared `progressHandler` must keep identity semantics.
5. **C12 Stremio ladder** → `IptvStremioLadder(bridge, handler, callbacks)`; Callbacks: `tune(url)` (→ `setIptvMediaItem`
   for current entry), `mirrorSources(candidates, index)`, `clearSources()`, `renderSourceBrowser()`,
   `dropStaleSourceSwitchFeedback()`, `currentChannelName()`, `toast()`, `isAlive()`. Medium: shares `progressHandler`
   with onDestroy's `removeCallbacksAndMessages(null)`; `stremioSources` is movie-mode state shared with sources panel.
6. **C4 EPG** → `IptvEpgController` (requestIptvEpg + ensure/stale/retry policy + schedule pane). Callbacks:
   `bridge()`, `onCurrentEntryEpgUpdated(entry)` (header + start-over + banner), `notifyRowEpg(entry)`,
   `isGuideVisible()`, `isAlive()`. Medium: per-entry mutable EPG fields, 45 s watchdog Handler not owned by any
   teardown, RecyclerView-layout re-entrancy invariant (async delivery comment @11550–11556).
7. **C5 start over / catch-up** → small controller with token; needs C7/C11 callbacks (`switchTo`, `tune`, `beginPlayback`,
   `replaceWithReplay`). Medium-high: replay path rewrites `iptvChannels`/`currentIptvIndex`.
8. **C3 + C6 + C7 browse/zap engine** → highest risk. Tightly coupled token protocol (`iptvUiContextToken`,
   `iptvBrowseToken`, `iptvZapRequestToken`, `iptvZapOwnsUiContext`, `iptvZapRequestInFlight`) spans browse, zap,
   jump, onDestroy (19330–19335). Owns the canonical `iptvChannels`/`currentIptvIndex` list also mutated by C5, C11
   callers and guide code outside the chunk. Extract only as one unit (a `IptvZapSession` owning channels+index+tokens)
   with Callbacks: `switchTo(entry, checkpoint)`, `onWindowInstalled()` (adapter/chrome/banner/header refresh),
   `commitSearch()`, `bridge()`, `toast()`.
9. **C11 tune pipeline** → highest risk; entangled with twin-trial, strict-TS, live recovery, recording finalisation
   and Media3 ordering. Leave in activity until those subsystems (outside this chunk) are extracted.

---

## 5. Lifecycle / teardown facts

- `onDestroy`@19270: `cancelPendingIptvCatchupRequest()`@19271 (bumps `iptvCatchupToken`);
  `iptvBrowseHandler.removeCallbacksAndMessages(null)`@19329 (retires C4 60 s retry, C7 settle + 2 s registration
  fallback); then `iptvEpgToken++`, `iptvUiContextToken++`, `iptvBrowseToken++`, `iptvZapRequestToken++`,
  `iptvZapRequestInFlight=false`, `iptvZapPendingInputs.clear()` (19330–19335);
  `progressHandler.removeCallbacksAndMessages(null)`@19376 (retires C8 hide/tick tokens and C12 stall watchdog) — all
  before player release (~19388). `finalizeIptvRecordingIfActive()`@19322 precedes them.
- `onStop`@19122 calls `cancelPendingIptvCatchupRequest()`@19126.
- Not covered by teardown: `requestIptvEpg`'s private `Handler(Looper.getMainLooper())` 45 s watchdog (11576) is never
  removed — after destroy it still delivers `null` into `ensureIptvChannelEpg`'s callback (mutates entry fields,
  calls adapter/header/banner painters on a dead activity; the schedule-pane callback checks `isDestroyed`, the
  now/next callback does not). `iptvStremioToken` is not bumped in onDestroy; the `runOnUiThread` resolve callback
  @14515 guards only `isFinishing`.
- C8 layout listeners (12598, 13700, 13805) and the banner view added to `android.R.id.content` are never removed
  (die with the window). Glide requests use `Glide.with(this)` (activity-scoped, auto-cleared).
- Ordering invariants to preserve: `checkpointCurrentIptvPosition` before `currentIptvIndex` moves (12354, 12101);
  `finalizeIptvRecordingIfActive` at the start of `beginIptvPlayback` (14484) and before stream identity flips in
  `setIptvMediaItem` (14288); `currentIptvHttpHeaders` set before `setMediaItem` (14300);
  `subtitleTrackReadiness.onMediaReplacement()` before each `setMediaItem`; `currentIptvStreamUrl=null` + `player.stop()`
  before async Stremio resolve (14500, 14512); `consumeCachedAdjacentIptvCategory` copies cache before clearing (12316);
  in-flight flag reset keyed on request token not UI context (12016–12020); banner tick only rescheduled on
  (re)entry (13662).

---

## 6. JVM tests (android/app/src/test)

- No test references any function or field of this chunk by name (grep of all chunk function names, `iptv*`,
  `guideStyle`, `guideTokens`, `dockSkinSpec`, `controlsSkin`, `lastLiveChannel*` across `src/test`: zero hits).
- Indirect only: `tv/StremioTvStartupWatchdogTest.kt` (Robolectric, builds the activity, sets `isIptvMode` by reflection
  @70; `iptvStillBypassesTheVodWatchdog`@278 — VOD watchdog, not this chunk). `tv/TvControlsSkinTest.kt` tests
  `TvControlsSkin.fromPref` only (the parse C9 calls). `tv/IptvDeviceQuirksTest.kt` covers `iptvStartsWithStrictTs`
  input to C11. `profiles/NativePlayerRejectedLaunchTest.kt` / `NativePlayerSettingsConsumptionTest.kt` launch the
  activity (would catch lazy-init crashes in C9 only if reached). `GuideStyle`/`GuideTokens` have no tests.
- Gaps needing characterization before extraction (Robolectric with a fake MethodChannel/bridge, since all bridge
  access is static `MainActivity.getAndroidTvPlayerChannel()` — a seam must be introduced first):
  - C6: zap within window / page boundary queueing (cap 24) / adjacent-category crossing with cache hit & miss /
    empty-category skip / stale response after `requestIptvBrowse` (uiContext token) / in-flight reset on superseded
    token / hidden-window trimming / bootstrap fallback restore.
  - C3: stale browse result rejected when zap owns UI context; search-focus retention.
  - C4: stale/no-now retry deadline (`epgNowStopMs` reuse), catch-up metadata upgrade for current entry, 45 s watchdog
    null delivery, `adoptIptvEpg` only-real-data rule, day filtering in `selectIptvEpgDay`.
  - C5: archive eligibility matrix in `currentIptvStartOverProgramme`; airing vs replay paths; relevance check after
    guide closed / schedule token change.
  - C7: settle-window dedupe (pause/resume doesn't restart; zap supersedes) and `noteIptvLiveChannel` payload;
    2 s watch-registration fallback fires playback exactly once; VOD checkpoint banding 0.02–0.95.
  - C8: show/alreadyUp/sameChannel repaint rules, docked vs floating auto-hide, tick self-reschedule, styled vs classic
    selection by `guideTokens`, hint gating (single channel / favourites source).
  - C12: ladder advance on error, exhaustion keeps key + rows and reports failure, stall watchdog token/index guard,
    winner reported once, manual pick re-arms.
  - C11: HLS-forced retry only once per URL and only for `UnrecognizedInputFormatException` in cause chain; startAt only
    for non-live; strict-TS decision inputs.

---

## AndroidTvTorrentPlayerActivity.kt — responsibility map, chunk E (lines 14759–20177)

File: `android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt`.
All line numbers are from the current HEAD (39c630303). "(w)" = written, otherwise read.
Fields declared *inside* this chunk are flagged "in-chunk".

---------------------------------------------------------------------------------------------------
## 1. Responsibility clusters

### C1. Unified menu model builder — 14759–15058, 15402–15619
Functions: umAudioTracks@14766, umAudioSelectedIndex@14784, mrow@14808, umSectionRows@14814,
unifiedMenuCallbacks@14828 (object: buildModel, onSectionActivated, onSearchSubmit, searchInitialQuery,
stylePreview, onHidden), umAudioModel@14895, umSubsModel@14929, umEmbeddedTrackRows@14973,
umAddonTrackRows@14994, umAppearanceRows@15020, umTimingRows@15025, umSearchRows@15402,
umPickSearchResult@15425, umSelectSubtitleRowIndex@15445, umSelectStremioSubtitleByUrl@15453,
umSourceRows@15472, umAddLoadMoreRow@15490, umSourcesModel@15504, umDisplayModel@15550, umPlaybackModel@15565.
Owns (in-chunk): subtitleSearchResults@14799, subtitleSearchStatus@14800, pendingSeriesResult@14801,
pendingSeason@14802, pendingEpisode@14803, unifiedSectionIds@14806. Also uses unifiedMenu@1200 (built at 2549–2562 with
`callbacks = unifiedMenuCallbacks, sectionIds = unifiedSectionIds`). Outside writers of C1 state: 4804/4806 (resetSubtitleState clears search state).
Fact: unifiedSectionIds = [audio, subs, display, playback]; the "sources" branches at 14834 and 14842 are unreachable via index
(umSourcesModel@15504 is only reachable through that branch).
Reads other clusters: player@262, trackSelector@264 (w params), subtitleTracks@1209, currentSubtitleTrackIndex@1210 (w),
userManuallySelectedSubtitle@1231 (w), stremioSubtitles@1214, addonSubtitleResults@1215, currentStremioSubtitleIndex@1227,
isLoadingStremioSubtitles@1229, manualSubtitleSeason@1235/Episode@1236, externalSubtitleActive@1290, activeExternalSubtitleUrl@1291,
autoSyncRunning@812, autoSyncResultLabel@1319, autoSyncResultUrl@1320, nightModeIndex@842, nightModeLabels@1360,
resizeModeIndex@840 (w), resizeModes@1347, resizeModeLabels@1354, playbackSpeedIndex@841, playbackSpeedLabels@1357,
sleepTimerMode@1269, sleepTimerMinuteOptions@1273, iptvChannels@863, currentIptvIndex@864, continuousShuffleEnabled@855 (w),
stremioSources@1089, currentStremioSourceIndex@1090, seriesSourceTabs@1158, seriesPacksFetched@1159, seriesEpisodesFetched@1160,
movieMoreSources@1163, movieSourcesFetched@1164, moreSourcesLoadingMode@1165, sourceBrowser@1201.

### C2. Legacy track dialogs + labels — 15621–15727
showAudioTrackDialog@15621 (caller 4455), showSubtitleTrackDialog@15663 (NO callers — dead), buildAudioTrackLabel@15703,
buildSubtitleTrackLabel@15718 (also used by C1 and C3). No owned fields. Reads player, trackSelector (w params).

### C3. Subtitle track list, settings panel, selection apply, style/offset apply — 15729–15943, 16409–16470
rebuildSubtitleTrackList@15733, subtitlePanelCallbacks@15784 (object; wired at 2545), showSubtitleSettingsPanel@15808 (caller 4466),
hideSubtitleSettingsPanel@15814 (NO callers — dead), showSyncOverlay@15818, refreshSubtitlePanelForLoading@15860
(callers 4977, 5213, 5224, 6552), isSearchSubtitleOption@15865, isLoadingSubtitleOption@15869, isExternalSubtitleOption@15873,
applySelectedSubtitleTrack@15877, isSideRenderableSubtitle@15940 (callers 5087, 5138), currentSubtitleIdentity@16419 (caller 3089),
applySubtitleSettings@16435 (caller 3090), applyAndPersistSubtitleSettings@16464.
Owns (declared outside): subtitleTracks@1209, currentSubtitleTrackIndex@1210, subtitleSettingsVisible@1196, subtitlePanel@1197,
syncOverlay@1198, linePickerOverlay@1199, subtitleSeekHandler@1202, subtitleSeekRunnable@1203.
Reads/writes other: stremioSubtitles@1214, currentStremioSubtitleIndex@1227 (w), isLoadingStremioSubtitles@1229,
userManuallySelectedSubtitle@1231 (w), externalSubtitleActive@1290, activeExternalSubtitleUrl@1291, lastExternalCueText@1295 (w),
offsetRenderersFactory@340, subtitleOverlay@151, subtitleControlsLift@152, payload@818, currentIndex@819, player, trackSelector, playerView@139.

### C4. External side-rendered subtitle engine — 15945–16132
loadStremioSubtitle@15951 (caller 7010), onExternalSubtitleLoaded@15977, stopExternalSubtitleRendering@16054 (callers 4798, 6537, 6979),
startExternalSubtitleTicker@16080, renderExternalSubtitleCue@16093.
Owns: externalSubtitleCues@1289, externalSubtitleActive@1290, activeExternalSubtitleUrl@1291, externalSubtitleLoadToken@1292,
externalSubtitleHandler@1293, externalSubtitleTicker@1294, lastExternalCueText@1295. Uses subtitleScope@1238.
Writes other: failedSubtitleUrls@1226, currentStremioSubtitleIndex@1227, trackSelector params, autoSyncResultLabel/Url,
autoSyncAppliedOffsetMs@1337. Reads subtitleSettingsVisible@1196, payload/currentIndex (via currentSubtitleIdentity).

### C5. Subtitle auto-sync (aligner, ladder, verify, pill UI) — 15060–15400, 16191–16407
runSubtitleAutoSync@15069, startAutoSyncLadder@15236, cancelAutoSyncLadder@15268, scheduleAutoSyncVerify@15274,
cancelAutoSyncVerify@15289, maybeRunAutoSyncVerify@15303, isAutoSyncPrefEnabled@15395, AutoSyncColors@16200 (private object),
AutoSyncRingView@16207 (private inner class View), ensureAutoSyncPill@16260, openAutoSyncPillWindow@16312,
stopAutoSyncPillWindow@16325, showSyncToast@16339, revealAutoSyncPill@16381, hideAutoSyncPillView@16393 (field-runnable 1313),
hideAutoSyncCard@16403 (field-runnable 1316).
Owns: autoSyncRunning@812, autoSyncPill@1302, autoSyncPillRing@1303, autoSyncPillLabel@1304, autoSyncPillResultShowing@1305,
autoSyncPillWindowActive@1306, autoSyncPillAnnounceShowing@1307, autoSyncPillAnnounceDismissRunnable@1310,
autoSyncCardHideRunnable@1316, autoSyncResultLabel@1319, autoSyncResultUrl@1320, autoSyncLadderSec@1327, autoSyncLadderIdx@1328,
autoSyncLadderDone@1329, autoSyncLadderTick@1330, autoSyncAppliedOffsetMs@1337, autoSyncVerifyTick@1338, autoSyncVerifyMisses@1339.
Reads other: speechTap@811 (assigned elsewhere), externalSubtitleActive, activeExternalSubtitleUrl, externalSubtitleHandler (shared
Handler with C4/C6), subtitleScope@1238, player position/isPlaying.
Invariant to preserve: runSubtitleAutoSync catches `Throwable` (15120, MiBox OOM) while maybeRunAutoSyncVerify catches `Exception` (15348);
both rethrow CancellationException; both clear autoSyncRunning in `finally`.

### C6. Status pill — 16134–16189
ensureStatusPill@16138, showStatusPill@16163, showStatusPillTransient@16176 (1400 ms; callers 1821, 5506 + many in-chunk),
hideStatusPill@16181 (field runnable 1297). Owns statusPill@1296, statusPillHideRunnable@1297. Uses externalSubtitleHandler@1293 and dp@6644.
Shared sink for C4, C9, C10, C11.

### C7. Display / speed / audio-effects / player defaults — 16472–16648
cycleAspectRatio@16473 (caller 4474), applyResizeMode@16480 (caller 3093), cyclePlaybackSpeed@16490 (4484), applyPlaybackSpeed@16495,
syncAudioEffectSession@16519 (279, 1640, 2000), initializeLoudnessEnhancer@16529 (278, 1633, 2004), releaseLoudnessEnhancer@16547
(1995, 2003), loadPlayerDefaults@16560 (2041), showNightModeDialog@16608 (4428), applyNightMode@16619.
Owns: resizeModeIndex@840, playbackSpeedIndex@841, nightModeIndex@842, loudnessEnhancer@843, systemAudioEffectsEnabled@847,
resizeModes@1347, resizeModeLabels@1354, playbackSpeeds@1356, playbackSpeedLabels@1357, nightModeGains@1359, nightModeLabels@1360.
loadPlayerDefaults ALSO writes non-display state: displayMatchMode@266, displayModeController@267, skipSegmentsEnabled@848,
skipSegmentProviderId@849 (mixed responsibility). Reads playerPreferences@2012, nativeAudioRouting@263, ottSkinInstalled@224,
speedButton@204, playerView@139, controlsSkin@12713 (log only).

### C8. Progress reporting, recovery checkpoints, lifecycle diagnostics — 16650–16968
restartProgressUpdates@16651 (794, 4880, 6698, 14382), recordPlaybackLifecycle@16664 (1709), finish@16674 (override),
deliverProgress@16694, stageRecoveryCheckpoint@16744, acknowledgeRecoveryCheckpoint@16797, sendProgress@16801 (1453, 1710, 8383),
sendIptvProgress@16902, sendPlaybackMaintenanceState@16927 (1502), sendPlaybackActivityState@16937, sendFinished@16951.
Owns (in-chunk): progressSentCount@16656, progressAckCount@16657, lastProgressLogAt@16658, lastProgressAckAt@16659,
lastProgressBridgeAvailable@16660, finalProgressSnapshot@16661, finishProgressAttempted@16662.
Owns (outside): progressHandler@1363 (shared!), progressRunnable@1451, recoverySequence@1128 (w), locallyCompletedItemKeys@1446 (w),
recoveryCompletedItemKeys@1447 (w).
Reads other: sourcePersistenceSessionId@1119, recoveryProfileId@1120, recoveryDataGeneration@1121, recoveryTitle@1122,
recoverySeriesTitle@1123, recoveryImdbId@1126, recoveryStartedAtMs@1127, isIptvMode@862, iptvChannels@863, currentIptvIndex@864,
isStremioTvMode@1177, startupSourcesExhausted@1118, startupRecoveryConsumed@1113, startupFailoverCursor@1100,
manualSourceSwitchSnapshot@1133, manualSourceRestoreInProgress@1142, payload@818 (w: items[currentIndex] = copy at 16860),
currentIndex@819, currentStremioSourceIndex@1090, maxStableDurationMs@1438, playlistVisible@836, playlistAdapter@851,
playbackSpeeds/Index, resizeModeLabels/Index, player.

### C9. Episode fetch / adjacent navigation — 16970–17174
guideAdjacent@16971 (1771, 5257, 5295, 5325), requestEpisodeFetch@16993 (1773, 3646, 5259, 5297, 5515),
requestAdjacentEpisodeFetch@17064 (1781, 5263, 5302), requestQuickPlayNextEpisode@17150 (1790, 5269), formatTime@17163 (utility;
callers 7680–8076 only). Owns (in-chunk): episodeFetchInFlight@16988 (also read at 5474/5486 by shuffle).
Writes other: stremioResolutionToken@1093 (shared token with C11!), isAutoAdvancing@834. Reads hasAdjacentEpisodeResolver@1095, payload.

### C10. Startup failover gate + manual source-switch transaction + PikPak gate reprepare + diagnostics — 17176–17812
beginStartupFailoverIfEligible@17180 (2184), beginManualSourceCandidate@17238, commitManualSourceCandidate@17301 (796),
failManualSourceCandidate@17367 (1662, 1836, 4716, 6767), armStartupCandidate@17431, commitStartupCandidate@17497 (797, 1537),
failStartupCandidate@17566 (1655, 1856, 6771), failStartupResolution@17681 (4717), startupCandidateElapsedMs@17694,
isPikPakPlaybackItem@17698, currentPlaybackItemIsPikPak@17702 (1535, 1818, 1826, 1845, 5440), cancelPikPakGateReprepare@17705
(6754, 6830, 6905), schedulePikPakGateReprepare@17715 (1834, 1854, 6860), startupWatchdogShouldExtend@17747,
startupSourceFields@17761, diagnosticProvider@17775 (2121), startupLog@17784, mediaServerPlaybackLog@17795 (790, 1813),
sourceSelectionLog@17804 (2657).
Owns: startupFailoverCursor@1100, startupFailoverGeneration@1101, startupFailoverTimeout@1102, startupCommitCheck@1103,
startupFirstFrameAtElapsedMs@1104, startupCandidateStartedElapsedMs@1105, startupFailoverDispatching@1106, startupTryNextOnFailure@1107,
startupMaxAttempts@1108, startupResolverProvider@1109, startupRecoveryAvailable@1110, startupHasRemainingSavedSources@1111,
startupRecoveryFetching@1112, startupRecoveryConsumed@1113, startupRecoveryProducedCandidates@1114, startupRecoveryNextMode@1115,
startupRecoveryCandidateIndices@1116, startupFailedReleases@1117, startupSourcesExhausted@1118, startupPikPakTorrentAcquisitionAttempted@1129,
manualSourceSwitchSnapshot@1133, manualSourceSwitchIndex@1134, manualSourceSwitchTimeout@1135, manualSourceCommitCheck@1136,
manualSourceFirstFrameAtElapsedMs@1137, manualSourceCandidateStartedElapsedMs@1138, pikPakGateReprepare@1139,
manualSourceMediaReplaced@1140, manualSourceCandidateUrl@1141, manualSourceRestoreInProgress@1142, startupGateView@140, startupGateStatus@141.
Reads/writes other: stremioSources, currentStremioSourceIndex (w), stremioResolutionToken (w), payload (w restore 17385–17392),
currentIndex (w), titleView@143 (w), isStremioTvMode, isIptvMode, controlsMenuVisible@835, moreSourcesLoadingMode, seriesSourceTabs,
movieMoreSources, pikPakRetryId@1370, mediaPreparationGeneration@823, sourceBrowser, progressHandler (shared).

### C11. Stremio source switcher + source list/fetch — 17814–17900, 17944–18910
setupStremioSources@17814 (2144, 14560), updateStremioQualityBadge@17832 (14593), watchSourceSwitchOutcome@17846 (14605),
cancelSourceSwitchWait@17883, dropStaleSourceSwitchFeedback@17896 (4604, 12356, 14619), onStremioSourceSelected@17944 (2659),
resolveStremioSourceViaFlutter@18003, resolveSourceToPlaylistViaFlutter@18083, requestMoreTorrentSources@18181 (2636),
applyMoreTorrentSources@18224, requestAddonTorrentSources@18272 (2651), applyAddonEpisodeSources@18312, failAddonFetch@18363,
adoptSourceList@18370, failMoreTorrentSources@18389, switchToSourcePlaylist@18404, rebuildNavigationMaps@18709,
switchToStremioSource@18752, showStremioSourceBadge@18866 (7500), hideStremioSourceBadge@18888 (7549, 7571),
hideStremioSourceBadgeImmediately@18905 (7498).
Owns (in-chunk): sourceSwitchReadyListener@17837, sourceSwitchTimeoutRunnable@17838.
Owns (outside): stremioSources@1089, currentStremioSourceIndex@1090, stremioSourceBadge@1091, stremioSourceBadgeText@1092,
stremioResolutionToken@1093, hasPlaylistResolver@1094, seriesSourceTabs@1158, seriesPacksFetched@1159, seriesEpisodesFetched@1160,
movieMoreSources@1163, movieSourcesFetched@1164, moreSourcesLoadingMode@1165, sourceAddons@1172, addonFetchState@1173, addonPackProbing@1174.
Writes other: payload items/maps (18421–18428 restore lambda, 18642–18647, 18710–18747, 18784), currentIndex, shuffleBag@856 (clear),
percentSeekApplied@825, resumeHoldArmedAtMs@1389, activeVodHeaders@820, mediaPreparationGeneration@823 (++ at 18767),
pikPakRetryId@1370, pikPakRetryCount@1369, isPikPakRetrying@1368, titleView, manualSourceMediaReplaced/CandidateUrl (C10),
startupRecoveryFetching/ProducedCandidates/CandidateIndices/NextMode (C10, in 18254–18264, 18398–18401), isAutoAdvancing (via C9).
Reads ottSkinInstalled@224, ottSourcesButton@250, isIptvMode, iptvStremioChannelKey@1079, subtitleTrackReadiness@1230.

### C12. Payload parsing — 18912–19081
parsePayload@18912 (caller 2105; reflection-called by StremioTvStartupWatchdogTest). Returns PlaybackPayload but ALSO writes:
stremioSources/currentStremioSourceIndex (only if JSON array non-empty), hasPlaylistResolver@1094, hasAdjacentEpisodeResolver@1095,
customShuffleEpisodes@1096, startupTryNextOnFailure@1107, startupMaxAttempts@1108, startupResolverProvider@1109,
startupRecoveryAvailable@1110, startupHasRemainingSavedSources@1111, sourcePersistenceSessionId@1119, networkPatience@1147,
networkBuffer@1148, iptvDecoderMode@1152, seriesSourceTabs..movieSourcesFetched@1158–1164, moreSourcesLoadingMode=null,
sourceAddons@1172, clears addonFetchState/addonPackProbing/locallyCompletedItemKeys/recoveryCompletedItemKeys; startupLog.

### C13. Activity lifecycle overrides + back handling + buffering indicator — 19083–19438
onStart@19083, onStop@19122, setupBackPressHandler@19161 (2177, 8867), legacyStoragePermissionRequestCode@19205 (in-chunk; used
9461, 9547), notificationPermissionRequestCode@19206 (in-chunk; used 9433), onRequestPermissionsResult@19208, onResume@19220,
onPause@19237, showBufferingIndicatorDebounced@19247 (1645), hideBufferingIndicator@19260 (1524, 1659, 4610), onDestroy@19270.
Buffering sub-cluster owns bufferingHandler@1448, bufferingDebounceRunnable@1449; reads bufferingIndicator@1374, hasEverBeenReady@1377,
nextOverlay@156, pikPakReactivationIndicator@1375 (800 ms debounce).
onStart reads sleepStopLatched@1282, iptvStoppedAtRealtime@359, iptvStartOverActive@865, iptvLiveRecovery@369.
Back handler reads linePickerOverlay, syncOverlay, iptvGuideVisible@1008, playlistOverlay@153, lastBackPressTime@859 (w).

### C14. Stremio TV channel guide + guide-ready wait — 17902–17942, 19441–20123
guidePanelReadyListener@17902 (in-chunk), guidePanelTimeoutRunnable@17903 (in-chunk), hideGuideWhenReady@17905, cancelGuideWait@17937,
initStremioTvGuide@19445 (2151), setupStremioTvGuide@19488, showStremioTvGuide@19543 (7317), hideStremioTvGuide@19568 (7133),
toggleStremioTvGuide@19578, filterStremioTvChannels@19582, updateStremioTvGuideHeader@19596, buildNowPlayingText@19638,
isFocusInStremioTvGuideList@19648 (7137, 7142), requestGuideDataForVisibleChannels@19659, updateStremioTvGuideChannelData@19763,
updateStremioSourcesFromPlaybackMap@19788, replacePayloadWithStremioTvItem@19805, playStremioTvPlaybackMap@19857,
requestStremioTvNext@19947 (1762, 5245), switchToStremioTvChannel@20038.
Owns: isStremioTvMode@1177 (w in init), stremioTvChannels@1178, stremioTvGuideOverlay@1179, stremioTvGuideList@1180,
stremioTvGuideSearch@1181, stremioTvGuideCountText@1182, stremioTvGuideNowPlaying@1183, stremioTvGuideNowPoster@1184,
stremioTvGuideNowLetter@1185, stremioTvGuideCurrentName@1186, stremioTvGuideCurrentTitle@1187, stremioTvChannelAdapter@1188,
stremioTvGuideVisible@1189, stremioTvChannelSwitchInProgress@1190, stremioTvNextInProgress@1191, stremioTvSwitchToken@1192.
Writes other: stremioSources/currentStremioSourceIndex (19792–19800), payload (19844–19853, startAtPercent 19888), currentIndex,
ottShowName@254, percentSeekApplied@825, pendingSeekMs@824, pendingItemTraktPercent@830, hasEverBeenReady@1377, nextText@157,
nextSubtext@158, stremioSourceBadge visibility. Reads playlistMode@850, ottSkinInstalled, ottSourcesButton, playerView.

### C15. companion object constants — 20129–20175 (PROGRESS_INTERVAL_MS 5_000, STARTUP_FAILOVER_TIMEOUT_MS 12_000,
STARTUP_WATCHDOG_RECHECK_MS 3_000, STARTUP_SLOW_SOURCE_MAX_WAIT_MS 45_000, STARTUP_PIKPAK_MAX_WAIT_MS 120_000,
PIKPAK_GATE_REPREPARE_DELAY_MS 4_000, EXTERNAL_SUBTITLE_TICK_MS 250, BACK_PRESS_INTERVAL_MS 2000, labels/prefixes, PikPak retry consts).

---------------------------------------------------------------------------------------------------
## 2. External effects per cluster

| Cluster | MethodChannel (MainActivity.getAndroidTvPlayerChannel) | Prefs / storage / network | Media3 | Timers / async | Views / focus |
|---|---|---|---|---|---|
| C1 | indirect: requestSubtitleCatalogSearchFromFlutter@6294 | SubtitleSettings reads (stylePreview 14876–14889) | trackSelector.parameters (audio override/disable 14911–14918); currentTracks | — | unifiedMenu render/hide; sourceBrowser.show; Toast 15604 |
| C2 | — | — | currentTracks; trackSelector params (AUDIO/TEXT) | — | AlertDialog 15645, 15687; Toast |
| C3 | `saveSubtitleAppearance` (16466) | SubtitleSettings.resetSyncOffset (15930), getFontSizeSp/buildCaptionStyle/getElevationPaddingFraction/getSyncOffsetMs | trackSelector clearOverridesOfType/setOverrideForType/setTrackTypeDisabled(TEXT); offsetRenderersFactory.setOffsetUs | subtitleSeekHandler.postDelayed(subtitleSeekRunnable,150) 16460 | Creates SubtitleLinePickerController/SubtitleSyncOverlayController on content root (15829, 15846); playerView.requestFocus; subtitlePanel show/hide/refresh |
| C4 | — | network+parse: SubtitleCueCache.fetch on Dispatchers.IO (15970); SubtitleSettings.recallSyncOffset/setSyncOffsetMs (16030–16032) | trackSelector TEXT disable/enable (15994, 16008, 16071); player.currentPosition | subtitleScope.launch; externalSubtitleHandler ticker 250 ms (16086) | subtitleOverlay.setCues |
| C5 | — | ProfilePreferenceProjection.getBoolean("subtitle_auto_sync_enabled", false) (15396); SubtitleSettings.setSyncOffsetMs (15154, 15360); SubtitleCueCache.get | player.isPlaying/currentPosition | subtitleScope.launch + Dispatchers.Default SubtitleAligner.alignTiered/align; externalSubtitleHandler: ladder 8_000 (15260, 15265), verify 90_000 then 120_000 (15286, 15281), announce dismiss 5_000 (16322), autoHideMs (16377) | pill LinearLayout added to android.R.id.content (16300); ValueAnimator pulse; non-focusable |
| C6 | — | — | — | externalSubtitleHandler 1400 ms (16178) | TextView added to android.R.id.content (16158); alpha animations |
| C7 | — | playerPreferences keys: player_default_aspect_index_tv, player_night_mode_index, player_system_audio_effects, content_display_match_mode, skip_segments_enabled, skip_segment_provider, player_default_subtitle_language (log) | playerView.resizeMode + content scale; nativeAudioRouting.update/setPlaybackSpeed/reprepare; LoudnessEnhancer(sessionId); AudioEffectSession.open | — | Toasts; AlertDialog 16609; speedButton text; refreshOttCaptionFor |
| C8 | `torrentPlaybackProgress` (with Result → ack) 16721; `torrentPlaybackMaintenanceState` 16928; `torrentPlaybackActivityState` 16939; `torrentPlaybackFinished` 16962 | TvPlaybackRecoveryStore.stage (sync)/stageAsync/acknowledgeAsync on filesDir; DiagnosticFileLog.recordCritical/recordError; PlaybackReturnHandoff.markReturning (16687) | duration/currentPosition/isPlaying/playbackState | progressHandler remove+postDelayed(progressRunnable, 5_000) | playlistAdapter.updateCurrentProgress |
| C9 | `requestEpisodeFetch` (17012, 17081 — two arg shapes); `requestQuickPlayNextEpisode` (17152) | — | — | runOnUiThread callbacks; token = ++stremioResolutionToken | status pill |
| C10 | `startupSourceFailed` (17575) | DiagnosticFileLog.record (startup_gate, media_server, source_selection) | player.stop (17413, 17590), prepare/play (17731–17732), playerError/playbackState/totalBufferedDuration | progressHandler: 12_000 timeouts (17294, 17460), 3_000 recheck (17287, 17452), 200 ms commit check (17326, 17528), 30_000 recovery guard (17621), 4_000 PikPak reprepare (17735), post (17674) | startupGateView visibility; R.id.startup_title animation; R.id.startup_back.requestFocus (17478); R.id.startup_explanation; Toast; finish() (17645) |
| C11 | `requestStremioSourceResolve` 18009; `requestSourcePlaylistResolve` 18092; `requestMoreTorrentSources` 18200; `requestAddonTorrentSources` 18287 (mode episodes) + 18335 (mode packs) | — | addListener/removeListener (17880, 17884); setMediaSource/setMediaItem/prepare/seekTo/play (18810–18821); subtitleTrackReadiness.onMediaReplacement | progressHandler 10_000 switch timeout (17858); runOnUiThread | badge animations; titleView; Toasts (18372, 18609); sourceBrowser render/showError |
| C12 | — | JSON only | — | — | — |
| C13 | via C8 | ActivityTracker.currentActivity; RecordingRegistry.removeListener; ConnectivityManager.unregisterNetworkCallback; unregisterReceiver(metadataUpdateReceiver) | player play/pause/release; iptvLiveRecovery | bufferingHandler 800 ms; handler purges in onDestroy | Back dispatcher; Toasts |
| C14 | `requestStremioTvGuideData` 19689; `requestStremioTvNext` 19974; `requestStremioTvChannelSwitch` 20055 | Glide poster load 19607 | addListener/removeListener (17934, 17938); setMediaItem/prepare/play (19911–19917) | progressHandler 10_000 guide timeout (17917), 1500 hideNextOverlay (20002); list.postDelayed 150 focus (19560) | findViewById R.id.stremio_tv_guide_*; RecyclerView + scroll listener; TextWatcher; R.id.debrify_playlist_button repurposed |

No BroadcastReceiver registration in this chunk (only unregister in onDestroy 19353–19360).

---------------------------------------------------------------------------------------------------
## 3. Coupling — outgoing calls to functions outside the chunk (name@definition line)

- C1: requestSubtitleCatalogSearchFromFlutter@6294, getCurrentSubtitleSearchItem@6239, buildSubtitleSearchInitialQuery@6594,
  currentSubtitleIdentityLabel@6627, retryAddonSubtitles@5192, applyManualSubtitleIdentity@6506, resolveSeasonEpisodeForSubtitle@6565,
  languageOfOverride@14266, onIptvSeriesAudioPicked@14254, updateAspectButtonLabel@7642, sleepTimerValueLabel@8342,
  startSleepCountdown@8348, armSleepAtEndOfItem@8361, cancelSleepTimer@8367, playRandom@5332, resetShuffle@5385.
  In-chunk: C2 labels, C3 apply/rebuild, C5 runSubtitleAutoSync, C3 showSyncOverlay, C7 applyNightMode/applyResizeMode/applyPlaybackSpeed,
  C11 onStremioSourceSelected/requestMoreTorrentSources.
- C2: languageOfOverride@14266, onIptvSeriesAudioPicked@14254.
- C3: showSearchSubtitleDialog@6025, currentSubtitleIdentityLabel@6627. In-chunk: C4 loadStremioSubtitle/stopExternalSubtitleRendering/renderExternalSubtitleCue.
- C4: tryAutoSelectAddonSubtitle@6915. In-chunk: C3 (currentSubtitleIdentity, applySubtitleSettings, refreshSubtitlePanelForLoading),
  C5 (startAutoSyncLadder, scheduleAutoSyncVerify, cancel*, showSyncToast), C6.
- C5: in-chunk only: C3 applySubtitleSettings; dp@6644.
- C6: dp@6644.
- C7: updateAspectButtonLabel@7642, refreshOttCaptionFor@4250, updateNightModeButtonLabel@7647.
- C8: heldResumePositionMs@1416. In-chunk: none besides itself (sendProgress → deliverProgress → stageRecoveryCheckpoint).
- C9: watchShufflePlayback@5435, yieldEpisodeFetchToQueuedShuffle@5456. In-chunk: C11 adoptSourceList/switchToSourcePlaylist, C6.
- C10: heldResumePositionMs@1416, reportValidatedSourceCommit@5966, setResolvingState@5899, rebuildPlaylistContent@3600,
  playItem@4556. In-chunk: C11 (cancelSourceSwitchWait, onStremioSourceSelected, requestMoreTorrentSources, failMoreTorrentSources,
  updateStremioQualityBadge, showStremioSourceBadge, hideStremioSourceBadgeImmediately), C8 restartProgressUpdates, C6.
  Pure helpers in StartupFailoverCursor.kt: isAioStreamsSource@26, isAioStreamsErrorSlate@35, startupRecoveryIsConsumed@15, StartupFailoverCursor.
- C11: cancelPikPakRetry@6900, heldResumePositionMs@1416, playItem@4556, rebuildPlaylistContent@3600, requestMetadataFromFlutter@2454,
  updateCatalogEpisodeControls@5317, attemptPikPakPlaybackLoop@6707, buildMergedSource@4919, discoverProtectedMime@4737,
  hidePikPakRetryOverlay@6891, originKey@2690, switchToIptvStremioSource@14588, hideControlsMenu@7535.
  In-chunk: C10 (armStartupCandidate, beginManualSourceCandidate, failManualSourceCandidate, failStartupResolution,
  failStartupCandidate, startupLog, startupSourceFields), C6. Pure: startupPlaylistSatisfiesEpisode@StartupFailoverCursor.kt:62,
  resolveSwitchedEpisodeTitle@SwitchedEpisodeTitle.kt:4, StremioSource.fromMap, PlaybackItem.fromMap.
- C12: in-chunk startupLog (C10). Pure: PlaybackItem.fromJson, StremioSource.fromJson.
- C13: restoreParkedIptvTwinIfNeeded@630, cancelPendingIptvCatchupRequest@11394, finalizeIptvRecordingIfActive@9654,
  parkIptvTwinTrialRestore@618, clearIptvTwinTrial@650, hideIptvReconnectPill@777, hideIptvGuide@10214, hidePlaylist@8643,
  updateRecordButtonState@9357, cancelPikPakRetry@6900, cancelSleepTimer@8367. In-chunk: C8, C4 ticker, C7 releaseLoudnessEnhancer, C11 cancelSourceSwitchWait.
- C14: hideControlsMenu@7535, cancelPikPakRetry@6900, clearStremioLoadingState@5219, fetchStremioSubtitles@4940,
  releaseResumeHold@1408, resetSubtitleState@4797, updateTitle@5597, fadeInNextOverlay@8656, hideNextOverlay@8663.
  In-chunk: C11 setupStremioSources/updateStremioQualityBadge.

Shared-resource hazards: (a) progressHandler@1363 is used by C8, C10, C11, C14 and purged wholesale in onDestroy (19376);
(b) externalSubtitleHandler@1293 is shared by C4, C5, C6 and purged wholesale (19410); (c) stremioResolutionToken@1093 is
incremented by C9 (17010, 17078), C10 (17379, 17587) and C11 (17973) — one token invalidates resolver callbacks AND episode fetches.

---------------------------------------------------------------------------------------------------
## 4. Extraction candidates (low → high risk)

1. **TvPayloadParser (C12)** — LOW. Pure JSON → return a `ParsedLaunchPayload` (PlaybackPayload + launch flags + sources) and have the
   activity assign fields in the same order. Needs no Callbacks. Risk: field assignment ordering (sources assigned only when array
   non-empty; sourcePersistenceSessionId defaulting to the current value 19014) and the startupLog line. Reflection test calls
   `parsePayload` by name — keep a private delegating method or update the test.
2. **Status pill (C6)** — LOW. `TvStatusPill(contentRoot, handler, dp)`; must keep using the SAME Handler as C4/C5 or onDestroy's
   `externalSubtitleHandler.removeCallbacksAndMessages(null)` (19410) stops covering it — give it a `release()` called at that point.
3. **Auto-sync pill view (C5 UI half: 16191–16407)** — LOW-MED. `AutoSyncPillView` with showToast/hide/openWindow/stopWindow; host
   needs content root, handler, dp. AutoSyncRingView is an inner class (captures activity only for nothing beyond Context) — movable.
4. **Track/display/audio settings (C2 + C7)** — LOW-MED. Labels (buildAudio/SubtitleTrackLabel) are pure. LoudnessEnhancer/night mode/
   speed need host: `player`, `nativeAudioRouting`, prefs, `updateNightModeButtonLabel`, `updateAspectButtonLabel`, `refreshOttCaptionFor`,
   `speedButton`. Split loadPlayerDefaults: display-match + skip-segment prefs belong elsewhere. Delete dead showSubtitleTrackDialog only
   as a separate, intentional change.
5. **Progress reporter (C8)** — MED. `TvPlaybackProgressReporter` owning the 7 counters, ack/recovery-store logic. Host: payload,
   currentIndex, player snapshot, startup/manual gate predicates (`isProgressSuppressed()`), heldResumePositionMs, recovery identity
   fields, channel accessor, filesDir, playlist refresh. Must keep `finalProgressSnapshot` toggling semantics (synchronous stage) in
   finish (16679–16683), onStop (19131–19133) and onDestroy (19281–19286) and `finishProgressAttempted` once-only latch.
6. **Stremio TV guide (C14 + guide-wait)** — MED. `StremioTvGuideController` with Callbacks: playStremioTvPlaybackMap pieces that touch
   payload/resume/subtitle state (resetSubtitleState, clearStremioLoadingState, releaseResumeHold, updateTitle, fetchStremioSubtitles,
   setMediaItem), hideControlsMenu, next-overlay fade, setupStremioSources. Shares progressHandler for 10_000/1500 runnables — needs
   own cancel in onDestroy.
7. **Unified menu model (C1)** — MED. `UnifiedMenuModelBuilder` implementing UnifiedMenuController.Callbacks. Host interface is wide
   (≈40 reads across subtitles, sources, audio, sleep, shuffle) — risk of "giant interface"; consider per-section providers
   (audio/subs/display/playback). The unreachable "sources" section must be preserved or removed deliberately.
8. **Subtitle engine (C3 + C4 + C5 logic)** — MED-HIGH. Natural `ExternalSubtitleRenderer` + `SubtitleAutoSyncCoordinator`. Host:
   player position, trackSelector TEXT params, subtitleOverlay, offsetRenderersFactory, subtitleControlsLift, identity content key,
   tryAutoSelectAddonSubtitle, subtitleScope. Hazards: load-token invalidation in stopExternalSubtitleRendering (16058); offset restore
   ordering in onExternalSubtitleLoaded (recall → apply → schedule verify → toast → ladder, 16029–16048); `::subtitleOverlay.isInitialized`
   guards; onStart/onStop ticker pause/resume; Throwable-vs-Exception catch asymmetry.
9. **Source switcher + list fetch (C11) and C9** — HIGH. Writes payload, currentIndex, playlist, resume hold, PikPak retry, media
   generation, shuffle restore lambda; shares the resolution token with C9/C10.
10. **Startup failover gate + manual transaction (C10)** — HIGHEST. Re-entrancy guard startupFailoverDispatching (17568–17678),
    generation counters, rollback restore of payload (17383–17416), finish() on exhaustion, recovery-fetch handshake with C11
    (requestMoreTorrentSources ↔ applyMoreTorrentSources/failMoreTorrentSources → failStartupCandidate("recovery-results")).
    Extract C10 and C11 together or behind one `SourceSwitchHost` interface: payload/currentIndex access, player, playItem,
    rebuildPlaylistContent, setResolvingState, reportValidatedSourceCommit, heldResumePositionMs, cancelPikPakRetry, status pill, finish.
11. **Lifecycle (C13)** — stays in the activity; only delegate (`controller.onStop()` etc.) once collaborators exist, preserving §5 order.

---------------------------------------------------------------------------------------------------
## 5. Lifecycle / teardown ordering (preserve verbatim)

finish() override 16674–16690: (1) if !finishProgressAttempted: finalProgressSnapshot=true → sendProgress(false) → finally
finalProgressSnapshot=false; finishProgressAttempted=true (16678–16686) (2) PlaybackReturnHandoff.markReturning(sourcePersistenceSessionId)
16687 (3) recordPlaybackLifecycle("finish_requested") 16688 (4) super.finish() 16689.

onStart 19083–19120: super.onStart 19084 → recordPlaybackLifecycle("activity_start") 19085 → sendPlaybackActivityState(true) 19086
(which also sends maintenance state 16943) → if !sleepStopLatched: live-IPTV twin restore (19105) / live rejoin via
playWhenReady=true + iptvLiveRecovery.userRetry("lifecycle-rejoin") when away > IPTV_LIVE_REJOIN_AFTER_MS (19107–19113) / else
player.play() 19115 → if externalSubtitleActive startExternalSubtitleTicker() 19119.

onResume 19220–19235: super.onResume → recordPlaybackLifecycle("activity_resume") → ActivityTracker.currentActivity=this → retry
unpublished recording publish + Toast.

onPause 19237–19245:
1. recordPlaybackLifecycle("activity_pause") 19238 (BEFORE super)
2. super.onPause() 19239
3. if ActivityTracker.currentActivity == this → null 19240–19242
4. cancelPikPakRetry() 19244

onStop 19122–19159:
1. cancelPendingIptvCatchupRequest() 19126 (before anything — blocks late catch-up restart)
2. recordPlaybackLifecycle("activity_stop") 19127
3. sendPlaybackActivityState(false) 19128
4. finalProgressSnapshot=true 19131; sendProgress(completed=false) 19132; finalProgressSnapshot=false 19133 (no try/finally here)
5. super.onStop() 19134
6. finalizeIptvRecordingIfActive() 19141
7. if (!parkIptvTwinTrialRestore()) clearIptvTwinTrial() 19151
8. iptvLiveRecovery.cancel() 19152
9. hideIptvReconnectPill() 19153
10. iptvStoppedAtRealtime = SystemClock.elapsedRealtime() 19154
11. player?.pause() 19155
12. externalSubtitleTicker?.let { externalSubtitleHandler.removeCallbacks(it) } 19158 (ticker field kept; onStart restarts)

onDestroy 19270–19438:
1. cancelPendingIptvCatchupRequest() 19271
2. displayModeController?.clear(); = null 19272–19273
3. mediaPreparationScope.cancel() 19274; mediaPreparationGeneration++ 19275
4. sourceBrowser?.destroy(); = null 19276–19277
5. recordPlaybackLifecycle("activity_destroy_begin") 19278
6. finalProgressSnapshot=true; try sendProgress(false) finally finalProgressSnapshot=false 19281–19286 (player still alive)
7. if initialized subtitleControlsLift.cancel() 19287
8. iptvTuneDiagnostics.onSessionEnd() 19288
9. remove+null: startupFailoverTimeout 19289–19290, startupCommitCheck 19291–19292, manualSourceSwitchTimeout 19293–19294,
   manualSourceCommitCheck 19295–19296, pikPakGateReprepare 19297–19298 (all from progressHandler)
10. manualSourceSwitchSnapshot=null, manualSourceSwitchIndex=null, manualSourceRestoreInProgress=false 19299–19301
11. startupFailoverGeneration++ 19302; startupFailoverCursor=null 19303
12. if initialized startupGateView GONE 19304
13. clearIptvTwinTrial() 19305; iptvLiveRecovery.cancel() 19306
14. unregister iptvNetworkCallback (ConnectivityManager, swallow) + null 19307–19314
15. RecordingRegistry.removeListener(recordingRegistryListener) 19315
16. cancelSleepTimer() 19318
17. finalizeIptvRecordingIfActive() 19322
18. if initialized seekFeedbackManager.destroy() 19325–19327
19. iptvBrowseHandler.removeCallbacksAndMessages(null) 19329; iptvEpgToken++, iptvUiContextToken++, iptvBrowseToken++,
    iptvZapRequestToken++ 19330–19333; iptvZapRequestInFlight=false 19334; iptvZapPendingInputs.clear() 19335
20. cancelPikPakRetry() 19338; pikPakRetryHandler.removeCallbacksAndMessages(null) 19339
21. if initialized pikPakReactivationIndicator: animate().cancel(), GONE 19342–19345
22. if initialized bufferingIndicator.animate().cancel() 19346; bufferingHandler.removeCallbacksAndMessages(null) 19347
23. upNextHandler.removeCallbacksAndMessages(null) 19350
24. unregisterReceiver(metadataUpdateReceiver) (catch+log) 19353–19359; = null 19360
25. subtitleScope.cancel() 19363; stremioSubtitles.clear() 19364; stremioSubtitleService=null 19365
26. skipSegmentFetchGeneration++ 19369; skipSegmentFetchJob?.cancel(); =null 19370–19371; skipSegmentScope.cancel() 19372; skipSegmentCache.clear() 19373
27. progressHandler / controlsHandler / seekbarHandler .removeCallbacksAndMessages(null) 19376–19378
28. releaseLoudnessEnhancer() 19381
29. AudioEffectSession.closeCurrent(this) 19385
30. player: recordPlaybackLifecycle("player_release_begin") → removeListener(playbackListener) → removeListener(subtitleListener) →
    release() → recordPlaybackLifecycle("player_release_complete"); RuntimeException → DiagnosticFileLog.recordError 19388–19400
31. player=null, subtitleListener=null, trackSelector=null, offsetRenderersFactory=null, speechTap=null, syncOverlay=null 19401–19406
32. linePickerOverlay?.hide(); =null 19407–19408
33. subtitleSeekHandler.removeCallbacks(subtitleSeekRunnable) 19409; externalSubtitleHandler.removeCallbacksAndMessages(null) 19410
34. SubtitleSettings.clearActiveSubtitleIdentityProvider(this) 19414
35. playlistView.adapter=null (if initialized); playlistAdapter/seriesPlaylistAdapter/moviePlaylistAdapter=null 19417–19420
36. focusRecoveryHandler.removeCallbacksAndMessages(null); focusRecoveryRunnable=null 19423–19424
37. cancelSourceSwitchWait() 19425 (NB: player already null → its removeListener is a no-op; timeout removal already done by step 27)
38. stremioSources.clear() 19426
39. seasonTabs.clear(); movieTabs.clear() 19429–19430
40. if initialized seekbarOverlay.setOnKeyListener(null) 19433
41. sendFinished() 19435 (MethodChannel `torrentPlaybackFinished`, after full teardown)
42. super.onDestroy() 19436
43. recordPlaybackLifecycle("activity_destroy_complete") 19437
Not cancelled explicitly in onDestroy: guidePanelReadyListener/guidePanelTimeoutRunnable (timeout covered by step 27; listener dropped with
player release), autoSync ladder/verify ticks and pill runnables (covered by step 33), autoSyncPill views (not removed).

Back handling (setupBackPressHandler 19161–19203) priority: linePickerOverlay → syncOverlay → iptvGuideVisible → playlistOverlay →
double-back within 2000 ms (records "back_exit", disables callback, re-dispatches) else Toast.

---------------------------------------------------------------------------------------------------
## 6. Existing JVM tests (android/app/src/test/kotlin) touching this chunk

Robolectric, reflection by private member NAME (extraction renames/moves will break them unless delegates are kept):
- tv/StremioTvStartupWatchdogTest.kt — parsePayload, initStremioTvGuide, beginStartupFailoverIfEligible (x12), commitStartupCandidate (x6),
  beginManualSourceCandidate, commitManualSourceCandidate, schedulePikPakGateReprepare, sendProgress (x3), cancelPikPakRetry,
  waitForPikPakMetadata; fields startupGateView, startupGateStatus, titleView, nextOverlay, pikPakReactivationIndicator, payload,
  isIptvMode, player, playbackListener, startupFailoverCursor, startupFailoverTimeout, startupSourcesExhausted, recoveryCompletedItemKeys,
  currentIndex, pikPakGateReprepare, manualSourceSwitchSnapshot, manualSourceSwitchTimeout, currentStremioSourceIndex. Covers C10, C12, part of C8.
- tv/ShufflePlaybackFlowTest.kt — field episodeFetchInFlight (C9), yieldEpisodeFetchToQueuedShuffle, watchShufflePlayback,
  mediaPreparationGeneration (outside-chunk shuffle logic).
- tv/SubtitleSyncDismissTest.kt — setupBackPressHandler + fields linePickerOverlay/syncOverlay; ON_STOP/ON_DESTROY lifecycle (C13).
- profiles/NativePlayerRejectedLaunchTest.kt — create→finish before views bound, then start/resume/pause/stop/destroy: exercises
  finish(), onStart/onStop/onDestroy `isInitialized` guards (C8, C13).
- profiles/NativePlayerSettingsConsumptionTest.kt — create() reads nightModeIndex/trackSelector after loadPlayerDefaults (C7);
  applySubtitleTrack/ensureDefaultSubtitleSelected/resetSubtitleState are outside this chunk.
- audio/NativeAudioRoutingTest.kt — source-text check only (setAllowInvalidateSelectionsOnRendererCapabilitiesChange), not this chunk;
  routing policy used by C7 applyNightMode/applyPlaybackSpeed.
Pure helper tests used by this chunk: StartupFailoverCursorTest (cursor, isAioStreams*, startupRecoveryIsConsumed,
startupPlaylistSatisfiesEpisode), SwitchedEpisodeTitleTest, TvPlaybackRecoveryStoreTest, PlaybackReturnHandoffTest, SubtitleAlignerTest,
UnifiedMenuControllerTest (controller only, fake callbacks — not the activity's model builder), SubtitleControlsLiftControllerTest,
TvSourceBrowserFocusTest, PlaybackItemHeadersTest.

Gaps needing Robolectric characterization before extraction:
- C1: no test of umAudioModel/umSubsModel/umSourcesModel/umPlaybackModel row shapes, selected flags, addon badge states, search flow
  (pendingSeriesResult season/episode clamp 1..99 / 1..999), "Load more" row states.
- C3: rebuildSubtitleTrackList index derivation (embedded + ⬇ external + loading row), applySelectedSubtitleTrack external-index math
  and sync-offset reset; applySubtitleSettings offset push only when identity != null + 150 ms debounce; currentSubtitleIdentity keys.
- C4: load-token staleness, failure fallback to previous index + TEXT re-enable, recall→verify ordering, stop re-enables TEXT, cue lookup
  (overlapping cues, offset subtraction, dedupe of identical text).
- C5: ladder rung gating (anchored seconds 20/45/90/180, offset==0), verify escalation after 2 misses, >400 ms residual re-sync,
  stale-URL discard, pref-off no-op, Throwable guard.
- C6/C5 UI: pill visibility timing (1400 ms, 5_000 announce, autoHide).
- C7: speed/night-mode route change → releaseLoudnessEnhancer; loadPlayerDefaults clamping & provider fallback; resize index 3 scale 4/3.
- C8: deliverProgress ack counting/log sampling, synchronous vs async recovery staging, completion-key latching, IPTV live skip,
  finish() once-only latch, sendFinished payload (startupSourcesExhausted/startupRecoveryConsumed).
- C9: requestEpisodeFetch / requestAdjacentEpisodeFetch result handling incl. episode_guide_unavailable fallback via guideAdjacent.
- C10: failStartupCandidate next-index filtering (externalUrl, failed release keys, PikPak acquisition), recovery-fetch handshake +
  30 s guard, exhaustion → finish(); failManualSourceCandidate rollback (payload/title/currentIndex restore, restore-in-progress replay).
- C11: switchToSourcePlaylist target matching (single/S-E/title/fallback first real episode), metadata carry-over, startup missing-episode
  reject, resume carry; switchToStremioSource held-resume + merged audio + PikPak path; applyMoreTorrentSources flags; adoptSourceList
  preferredSourceMissing toast; addon two-phase fetch; watchSourceSwitchOutcome READY/IDLE pills.
- C12: parsePayload field side-effects & defaults (only one fixture today).
- C13: exact onStop/onDestroy ordering (no test asserts order: progress-before-release, sendFinished last, catch-up cancel first).
- C14: channel switch revert on failure, token staleness, next-in-progress mutual exclusion, guide data merge.

---

## AndroidTvTorrentPlayerActivity.kt: split map F (read-only survey)

File: `android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt`, 22,221 lines.
Package `com.debrify.app.tv`. Imports 1-133. `@OptIn(UnstableApi::class)` at 135. Class 136-20177.
Companion object 20129-20176. Top-level declarations 20178-22221.
Revision: HEAD 39c630303 (clean tree).

---------------------------------------------------------------------------------------------------
## A. Top-level declarations (20178-22221)

General finding: none of the top-level declarations can reference activity instance members. They also
don't reference the companion's private consts. A grep for PAYLOAD_KEY, IMDB_ID_REGEX, PROVIDER_PIKPAK
and `AndroidTvTorrentPlayerActivity` in 20178-22221 returns 0 hits. Their only coupling is:
- **File-private visibility.** Most declarations are `private` top-level, which makes them file-private.
  If one moves to another file, it must become `internal` (or move together with every user in the same file).
- **R resources.** `com.debrify.app.R` comes from import line 108. A new file needs `import com.debrify.app.R`.
- **Other package-level helpers in tv/.** These already live in other files:
  - `SourceQualityParser`
  - `ProtectedStreamHttp`
  - `GuideTokens` and `GuideStyle` (IptvGuideStyle.kt)
  - `sourceBadgeDescription` (TvSourceBadgeText.kt)
  - `sourceAddonPresentation` (SourceAddonPresentation.kt)
  - `startupFailureKey` (StartupFailoverCursor.kt)
  - `nullableString` (NullableJsonString.kt)
  - Glide, media3 `UnstableApi`

Use counts below are `grep -w` line counts: "act" = lines 1-20177, "top" = lines 20178+.

| Decl | Lines | Vis | R refs | Deps / notes | Users |
|---|---|---|---|---|---|
| `PlaylistMode` enum | 20178 | private | - | - | act 16 |
| `ManualSourceSwitchSnapshot` | 20180-20190 | private | - | PlaybackItem, JSONObject | act 2. Field name `manualSourceSwitchSnapshot` is reflected by a test (C) |
| `CollectionGroup` | 20192-20195 | private | - | - | act 4, MovieGroups |
| `MovieGroups` | 20197-20212 | private | - | CollectionGroup | act 6, MoviePlaylistAdapter |
| `MovieTab` | 20214-20218 | private | - | TextView | act 2 |
| `PlaylistOverlayAdapter` iface | 20220-20224 | private | - | - | act 1, PlaylistAdapter, MoviePlaylistAdapter |
| `StremioSource` (+companion `fromJson` 20280 / `fromMap` 20305 / `parseQuality`) | 20230-20334 | private | - | startupFailureKey, sourceBadgeDescription, sourceAddonPresentation, nullableString, SourceQualityParser, TvSourceBadgeResult | act 10 |
| `PlaybackPayload` | 20336-20358 | private | - | PlaybackItem, GuideEpisode, JSONObject | act 5. **Test reflects field `items`** on it (C) |
| `mergeLateMetadataResumePosition` | 20365-20377 | internal | - | pure | act 1 (metadata handler); LateEpisodeMetadataMergeTest; Dart source test |
| `mergeLateMetadataDuration` | 20380-20391 | internal | - | pure | same as above |
| `GuideEpisode` | 20394-20407 | private | - | - | act 2, PlaybackPayload, PlaylistAdapter |
| `PlaybackItem` (+`seasonEpisodeLabel` 20448, `displayProgressPercent` 20464, companion `fromJson` 20480 / `fromMap` 20508) | 20409-20516 | **internal** | - | ProtectedStreamHttp.headers | act 42; PlaybackItemHeadersTest; PlaybackProgressPolicyTest (`fromJson`, `fromMap`, `copy`, `httpHeaders`, `episode`, `resumePositionMs`, `displayProgressPercent`, `traktProgressPercent`, `allowLocalProgressDisplay`). Dart test pins `if (watched) return 100` (20465) |
| `SubtitleCatalogResult` | 20518-20535 | private | - | - | act 14. Torbox has its OWN Java copy (TorboxTvPlayerActivity.java:4790), not shared |
| `SeasonEpisode` | 20537-20540 | private | - | - | act 6 |
| `PlaylistListItem` sealed (SeasonHeader / Episode / MissingEpisode) | 20543-20549 | private | - | - | PlaylistAdapter only (act 0) |
| `PlaylistAdapter` (+SeasonHeaderViewHolder 20752, EpisodeViewHolder 20771, companion 21094) | 20551-21099 | private | layouts `item_android_tv_playlist_entry_horizontal`, `item_android_tv_season_header`; ~25 ids `android_tv_playlist_item_*`, `season_header_*`, `now_playing_*`, `focus_border`, `shimmer_overlay`, `fallback_*`, `card_content`, `meta_separator` | PlaybackItem, GuideEpisode, PlaylistListItem, Glide | act 5. Dart test anchors at 20671 / 20691 (C) |
| `MoviePlaylistAdapter` (+MovieViewHolder 21198, companion 21186, inner companion 21390) | 21101-21408 | private | same row layout; ids incl. `selection_overlay`, `*_playing`, `*_progress_container`; `R.color.transparent` | MovieGroups, PlaybackItem, PlaylistAdapter ref (1 hit) | act 5 |
| `IptvChannelEntry` | 21413-21469 | private | - | - | act 52, IptvChannelAdapter. Comment banner at 21409-21412 |
| `IptvChannelAdapter` (`@androidx.annotation.OptIn` at 21471, companion 21494, ViewHolder 21500) | 21471-21788 | private | `item_iptv_channel` + 13 `iptv_channel_*` ids | GuideTokens, GuideStyle, IptvChannelEntry | act 2 |
| `IptvSourceEntry` | 21790-21802 | private | - | - | act 5 |
| `IptvListEntry` | 21805-21809 | private | - | - | act 5; nested IptvListPickerAdapter |
| `IptvEpgProgram` | 21811-21817 | private | - | - | act 6 |
| `IptvEpgAdapter` (ViewHolder 21833) | 21819-21920 | private | `item_iptv_epg_program` + 5 `iptv_epg_program_*` ids | GuideTokens, GuideStyle | act 2 |
| `StremioTvGuideChannel` | 21926-21946 | private | - | - | act 7 |
| `StremioTvGuideAdapter` (`@OptIn` at 21948, companion 21954, ViewHolder 21960) | 21948-22221 | private | `item_stremio_tv_guide_channel` + 14 `stremio_tv_guide_*` ids | StremioTvGuideChannel | act 3 |

No other main-source file references any of these names. The only exception is SubtitleCatalogResult,
and Torbox's is a same-named private Java class.

Extraction notes:
- The adapters are already outer-free. Every activity interaction goes through constructor lambdas,
  which makes them the lowest-risk move: a model file plus adapter files.
- Moving `PlaybackItem` or the merge funs keeps tests compiling as long as they stay
  `internal` in package `com.debrify.app.tv`.
- The Dart source test for PlaylistAdapter (C2) needs its anchors to stay in AndroidTvTorrentPlayerActivity.kt.
  Otherwise that test must be retargeted.

### A2. Nested types inside the activity

| Type | Lines | Kind | Captures outer? | Users (lines) | Notes |
|---|---|---|---|---|---|
| `IptvLiveLoadErrorPolicy` | 709-749 | `private inner class` extends DefaultLoadErrorHandlingPolicy | **YES**. `liveNow()` reads `iptvChannels` and `currentIptvIndex` | 2960 (installed on media source factory) | To extract, pass a `() -> Boolean` liveNow lambda. All other logic is pure |
| `TvSourceAddon` | 1171 | **public** `data class` (nested, static) | No | 1172, 19047 | Only public nested type. Binary name `AndroidTvTorrentPlayerActivity$TvSourceAddon`; no external users |
| `SkipSegmentRequest` | 1243-1250 | private data class (static) | No | 8135, 8154, 8199 | Pure |
| `SleepTimerMode` | 1268 | private enum | No | 414, 1269, 1680, 1715, 8337-8370, 15575, 15588 | - |
| `ShufflePlaybackAttempt` | 5394-5402 | private class (static) | No (pure holder; lambdas supplied by caller) | 4560, 5403-5528, 16998, 18411 | **Reflected by test by simpleName + 7-arg ctor order** (C). Keep it nested in the activity, or update ShufflePlaybackFlowTest |
| `IptvCategoryAdapter` (+ViewHolder 10611) | 10602-10672 | private class (static) | No | 10495 | Uses GuideTokens, `R.color.iptv_premium_button_text`, `R.drawable.iptv_premium_button_bg` |
| `IptvListPickerAdapter` (+ViewHolder 10854) | 10837-10909 | private class (static) | No | 10729 | Same R refs; uses IptvListEntry (top-level) |
| `DockSkinSpec` | 12727-12738 | private data class | No | 12742-12786 (`dockSkinSpec` lazy `when(controlsSkin)`) | Pure value; the lazy builder stays with the activity |
| `IptvStremioCandidate` | 14281 | private data class | No | 1080, 14701, 14723 | - |
| `AutoSyncColors` | 16200-16204 | private object | No | 15076-15367, 16043, 16208, 16316 | consts OK / FAIL / BUSY |
| `AutoSyncRingView` | 16207-16258 | `private inner class` : View | **Nominally** (inner holds `this@Activity`), but the body uses only its own fields (`arcColor`, `pulse`, `paint`, `pulseAnimator`) and `AutoSyncColors`. No outer member use | 1303 (field), 16262 (construct) | Can be made a non-inner top-level class with no behavior change |

---------------------------------------------------------------------------------------------------
## B. External contract surface (must stay byte-identical)

### B1. Manifest

`AndroidManifest.xml:186-192` declares `.tv.AndroidTvTorrentPlayerActivity` with:
- `exported="false"`
- `hardwareAccelerated="true"`
- `configChanges="keyboard|keyboardHidden|navigation|screenSize|screenLayout|smallestScreenSize|orientation|uiMode"`
- `screenOrientation="landscape"`
- theme `Theme.AppCompat.DayNight.NoActionBar`

The class FQN must not change.

### B2. Launch (Flutter → MainActivity → activity)

- **Dart channel.** `com.debrify.app/android_tv_player` is declared at MainActivity.kt:101 and wired at 2477.
  - `setAndroidTvPlayerChannel` is called at 2480.
  - Handler cases: `launchTorboxPlayback`, `launchRealDebridPlayback`, `launchTorrentPlayback`, `updateEpisodeMetadata`.
- **Launch method.** `MainActivity.handleLaunchTorrentPlayback` (MainActivity.kt:2930-3001):
  - It stages the payload JSON as `cacheDir/torrent_payload_<ms>.json`.
  - It starts the activity by string: `setClassName(this, "com.debrify.app.tv.AndroidTvTorrentPlayerActivity")` (MainActivity.kt:2979).
  - Before `startActivity`, it calls `TvPlaybackRecoveryStore.begin(filesDir, sessionId)` and `PlaybackReturnHandoff.begin(sessionId, ownerProfileId, generation)`.
- **Intent extras read by the activity:**
  - `"playbackSessionId"` (Int) at 2016, assigned to `sourcePersistenceSessionId`.
  - `"payloadPath"` at 2020 (diagnostic `hasExtra`) and 2044. The activity reads the file and **deletes** it.
  - Legacy fallback `PAYLOAD_KEY = "payload"` (companion 20130, public const) at 2068. **NativePlayerSettingsConsumptionTest uses this inline `"payload"` extra**, so the fallback is load-bearing for tests.
  - `NativePlayerPreferences.EXTRA` is read via `NativePlayerPreferences.fromIntent(this, intent)` at 2026. On exception the activity shows a Toast and calls `finish()` before `setContentView`. NativePlayerRejectedLaunchTest relies on finishing before views are bound.
- **Payload JSON schema.** `parsePayload(raw)` at 18912 builds `PlaybackPayload`, with `PlaybackItem.fromJson` at 20480 and `StremioSource.fromJson` at 20280.
  - `payloadCheck.optInt("sourcePersistenceSessionId", ...)` at 2088.
  - Dart producer: `lib/features/player_launch/data/android_tv_payload_builder.dart` and `lib/services/android_tv_player_bridge.dart`.

### B3. Broadcast (received; none sent by the activity)

- **Receiver.** `setupMetadataReceiver()` at 2188, which is called from onCreate at 2178 and from the IPTV-mode init path at 8868; each path also calls setupBackPressHandler().
  - Action: `"com.debrify.app.tv.UPDATE_EPISODE_METADATA"` (2207).
  - API ≥33 registers with `RECEIVER_NOT_EXPORTED` (2209); otherwise plain `registerReceiver` (2211).
  - `unregisterReceiver` at 19355 (onDestroy).
- **Extras read:**
  - `metadataUpdatesPath` (prefix `episode_metadata_`), with fallback `metadataUpdates`.
  - `imdbId`
  - `guideEpisodesPath` (prefix `episode_guide_`), with fallback `guideEpisodes`.
  - `showName`
- **Staged-file reads.** `readStagedExtra` (2229-2248) is read-only: it never deletes, and it rejects any file outside `cacheDir` or without the expected prefix.
- **Sender.** `MainActivity.handleUpdateEpisodeMetadata` at 2875-2928 (`sendBroadcast` with `setPackage`). It sweeps old staged files.
- **Handler.** `handleMetadataUpdate` at 2250. A Dart test anchors the section from `// Handle episode metadata updates` (2335) to `private fun requestMetadataFromFlutter()` (2454).

### B4. Activity → Flutter MethodChannel calls

All calls go through `MainActivity.getAndroidTvPlayerChannel()`, the `@JvmStatic` companion at MainActivity.kt:975-983. Every name below has a `case` in `lib/services/android_tv_player_bridge.dart` (bridge line in brackets). That bridge is shared with Torbox.

| Line | Method | Bridge line |
|---|---|---|
| 2475 | `requestEpisodeMetadata` | 1318 |
| 2607 | `requestStreamBadges` | 335 |
| 5936 | `requestTorrentStream` | 1288 |
| 5969 | `commitStremioSource` | 695 |
| 5996 | `requestMovieMetadata` | 1350 |
| 6306 | `searchSubtitleCatalogs` (also used by Torbox) | 1381 |
| 10753 | `setIptvChannelInList` | 1238 |
| 10788 | `getIptvChannelListMembership` | 1259 |
| 10936, 11878, 12000 | `requestIptvBrowse` | 1071 |
| 11035 | `setIptvFavorite` | 1219 |
| 11430 | `requestIptvCatchup` | 1086 |
| 11595 | `requestIptvEpg` | 1020 |
| 12449 | `noteIptvLiveChannel` | 1203 |
| 12493 | `recordIptvWatch` | 1171 |
| 14259 | `saveIptvSeriesAudio` | 433 |
| 14713 | `requestIptvStreamUrls` | 978 |
| 14753 | `reportIptvStreamResult` | 1269 |
| 16466 | `saveSubtitleAppearance` | 449 |
| 16721 | `torrentPlaybackProgress` | 510 |
| 16928 | `torrentPlaybackMaintenanceState` | 480 |
| 16939 | `torrentPlaybackActivityState` | 492 |
| 16962 | `torrentPlaybackFinished` | 891 |
| 17012, 17081 | `requestEpisodeFetch` | 827 |
| 17152 | `requestQuickPlayNextEpisode` | 1554 |
| 17575 | `startupSourceFailed` | 726 |
| 18008 | `requestStremioSourceResolve` | 524 |
| 18091 | `requestSourcePlaylistResolve` | 652 |
| 18199 | `requestMoreTorrentSources` | 742 |
| 18286, 18334 | `requestAddonTorrentSources` | 790 |
| 19689 | `requestStremioTvGuideData` | 559 |
| 19974 | `requestStremioTvNext` | 622 |
| 20055 | `requestStremioTvChannelSwitch` | 590 |

The activity **handles no inbound MethodChannel calls**. Flutter reaches it only through the launch intent and the
broadcast in B3. It also receives remote key and text injection through `ActivityTracker.currentActivity`:
- `onResume` at 19220-19223 sets it, and `onPause` at 19237-19242 clears it.
- MainActivity.kt:2561-2614 then calls `targetActivity.dispatchKeyEvent(...)`.
- That makes the `dispatchKeyEvent` override (7018) part of the remote-control contract.

Key payload keys pinned by tests:
- `"sourcePersistenceSessionId" to sourcePersistenceSessionId` (2608, 5973, 16931, 16941, 16953, 17576)
- `result["startupSourcesExhausted"] = true` (16956, inside `sendFinished` 16951)
- `"automaticRecovery" to (...)` (18087)
- `map["recoveryCandidateCount"]` (18260)

### B5. Other process and global touchpoints

- Lifecycle overrides: `onCreate` 2014, `dispatchKeyEvent` 7018, `finish` 16674, `onStart` 19083, `onStop` 19122, `onRequestPermissionsResult` 19208, `onResume` 19220, `onPause` 19237, `onDestroy` 19270.
- `finish()` calls `PlaybackReturnHandoff.markReturning(sourcePersistenceSessionId)` at 16687. `TvPlaybackRecoveryStore.stage`, `stageAsync` and `acknowledgeAsync` are called at 16791-16798.
- Recording:
  - `RecordingRegistry.addListener` (2040)
  - `LiveRecordingService` `ACTION_STOP` / `EXTRA_TASK_ID` via `startService` (9442-9445)
  - `ContextCompat.startForegroundService` (9510)
  - `RecordingAlarmReceiver`, `RecordingScheduleStore`
- Prefs:
  - `getSharedPreferences("debrify_permissions")` key `notification_permission_asked` (9427-9429)
  - `requestPermissions` with `notificationPermissionRequestCode` and `legacyStoragePermissionRequestCode`
  - `loadPlayerDefaults()` (16560) reads `player_night_mode_index`, `player_default_aspect_index_tv`, `player_system_audio_effects`, `content_display_match_mode`, `skip_segments_enabled` via NativePlayerPreferences
- Diagnostics: `DiagnosticFileLog` source `"android_tv_player"`, with events `activity_create`, `payload_read`, `payload_read_failed`, `payload_missing`, and others. Logcat tags include `AndroidTvPlayer`, `TVMazeUpdate`, `DebrifyStartupGate`, `DEBRIFY_PLAYER_DECODER`, `AutoSync`.
- Companion: the only public member is `PAYLOAD_KEY`. Everything else is private const and used only inside the activity. No `@JvmStatic` statics and no other external references.

---------------------------------------------------------------------------------------------------
## C. Tests coupled to internals (all break or need edits if code moves)

### C1. Kotlin reflection tests (android/app/src/test/kotlin/com/debrify/app/...)

`getDeclaredField` and `declaredMethods` are looked up on `activity.javaClass`. Any member that moves to a
helper class, or is renamed, breaks these tests. Methods are matched by **name + parameterCount** (`first { }`).

**tv/StremioTvStartupWatchdogTest.kt** (297 lines; Robolectric `buildActivity(...).get()`, no create). Helpers are at 31-40.
- Fields set:
  - `startupGateView`, `startupGateStatus`, `titleView`, `nextOverlay`, `pikPakReactivationIndicator`
  - `payload`, `isIptvMode`, `player`
- Fields read:
  - `startupFailoverCursor` (cast to `StartupFailoverCursor`, checks `.committed`)
  - `startupFailoverTimeout`, `startupSourcesExhausted`
  - `playbackListener` (cast to `Player.Listener`)
  - `recoveryCompletedItemKeys` (Set), `currentIndex`, `payload`, `pikPakGateReprepare`
  - `manualSourceSwitchSnapshot`, `manualSourceSwitchTimeout`, `currentStremioSourceIndex`
  - `startupGateView` (visibility)
- Reflected on the PlaybackPayload instance: `read(payload, "items")`, which requires a backing field named `items`.
- Methods called (name / arg count):
  - `parsePayload`/1, `initStremioTvGuide`/1(JSONObject)
  - `beginStartupFailoverIfEligible`/0, `sendProgress`/1(Boolean), `commitStartupCandidate`/0
  - `waitForPikPakMetadata`/5(item, Int, Int, Long, (Boolean)->Unit), `cancelPikPakRetry`/0
  - `beginManualSourceCandidate`/1(Int), `commitManualSourceCandidate`/0, `schedulePikPakGateReprepare`/1(null)

**tv/ShufflePlaybackFlowTest.kt** (118 lines; `buildActivity(...).get()`)
- Fields set: `queuedShuffleGeneration`, `queuedShuffleNavigation`, `episodeFetchInFlight`, `mediaPreparationGeneration`, `showShuffleGeneration`.
- Methods called: `yieldEpisodeFetchToQueuedShuffle`/0, `clearQueuedShuffle`/1, `watchShufflePlayback`/1, `failShufflePlayback`/0, `shuffleAttemptCurrent`/1, `resetShuffle`/0.
- Nested class lookup: `activity.javaClass.declaredClasses.first { it.simpleName == "ShufflePlaybackAttempt" }`, then the ctor with **7 params in order** `(navigation:Int, generation:Int, autoAdvance:Boolean, onUnavailable:()->Unit, mediaStarted:Boolean, restorePreparation:(()->Unit)?, finished:Boolean)`. This must remain a nested class of the activity.

**tv/SubtitleSyncDismissTest.kt** (90 lines; both ATV and Torbox)
- Fields set: `type.getDeclaredField("linePickerOverlay")` and `type.getDeclaredField("syncOverlay")`.
- Method: `getDeclaredMethod("setupBackPressHandler")` (no args), defined at 19161.

**profiles/NativePlayerSettingsConsumptionTest.kt** (149 lines; `buildActivity(..., intent).create()`)
- Intent extras: `NativePlayerPreferences.EXTRA`, `initialUrl`, `initialTitle`, `provider`, and an inline `payload` JSON (the legacy PAYLOAD_KEY path).
- ATV fields: `nightModeIndex`, `trackSelector` (DefaultTrackSelector).
- ATV method: `getDeclaredMethod("getControlsSkin")`, the getter of a Kotlin property `controlsSkin`. Its `toString()` must be `"OTT"` by default or `"FROST"` for custom. The other methods in this test (`applySubtitleTrack`, `ensureDefaultSubtitleSelected`, `resetSubtitleState`, `playerStyle`) target Torbox only.

**profiles/NativePlayerRejectedLaunchTest.kt** (39 lines): no reflection. `buildActivity(..., Intent()).create()` must leave `isFinishing == true` without views being bound (2026-2032).

**audio/NativeAudioRoutingTest.kt:66-79**: a source-text check, not reflection. It locates appDir by finding `src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt` and reads that exact file. It asserts the file contains `.setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)` (now at 2747) and does not contain `(false)`. The same check runs on TorboxTvPlayerActivity.java. The reflection names in that file (`bypassEnabled`, `initBypass`, `FfmpegAudioRenderer`) target other classes.

**Tests of top-level internals** (compile-level; safe if package and `internal` are kept):
- `tv/LateEpisodeMetadataMergeTest.kt`: mergeLateMetadataResumePosition and mergeLateMetadataDuration
- `tv/PlaybackItemHeadersTest.kt`: `PlaybackItem.fromMap`, `fromJson`, `copy`, `httpHeaders`, `episode`
- `tv/PlaybackProgressPolicyTest.kt`: `PlaybackItem.fromJson`, `displayProgressPercent()`, `copy(traktProgressPercent=, allowLocalProgressDisplay=)`, `resumePositionMs`

### C2. Dart source-text tests

All three Dart tests read `'android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt'` from the repo root.
`_between(src, start, end)` requires **start to occur first and end after it in the SAME file**. Moving either
anchor method or reordering them breaks the test.

**test/android_tv_auto_advance_resume_test.dart** (file at :15)
- `_between('private fun playItem(' [4556], 'private fun resolveAndPlay(' [4649])` contains:
  - `if (autoAdvance || suppressResume) 0L else item.resumePositionMs` (4634)
  - `if (autoAdvance || suppressTrakt || suppressResume) 0.0` (4636)
- `_between('private fun triggerUpNext()' [8771], 'private fun dismissUpNext()' [8779])`: `isAutoAdvancing = true` must appear before `playItem(target)`.

**test/android_tv_mdblist_progress_source_test.dart** (file at :179, :198)
- `_between('val synthetic = PlaybackItem(' [20671], '(holder as EpisodeViewHolder).bindMissing(synthetic)' [20691])`. This range is inside the top-level PlaylistAdapter. It contains:
  - `resumePositionMs = g.resumePositionMs`
  - `durationMs = g.durationMs`
  - `traktProgressPercent = g.trackerProgressPercent`
  - `watched = g.watched`
- `_between('// Handle episode metadata updates' [2335], 'private fun requestMetadataFromFlutter()' [2454])` contains:
  - `hasWatchedUpdate`
  - `model.items.indexOfFirst`
  - `it.season == updateSeason`
  - `mergeLateMetadataResumePosition`
  - `mergeLateMetadataDuration`
  - `traktProgressPercent = newTrackerProgress`
- Whole file contains `if (watched) return 100` (20465, in PlaybackItem).

**test/manual_source_validation_contract_test.dart** (`nativePlayer` defined at :17-18)

Whole-file `contains` assertions:
- `"automaticRecovery" to (startupFailoverDispatching && startupRecoveryCandidateIndices != null)` (18087)
- `startupResolverProvider.equals("pikpak", ignoreCase = true)` (17222 / 17599 / 17648)
- `startupPikPakTorrentAcquisitionAttempted = true` (17653)
- `map["recoveryCandidateCount"]` (18260)
- `startupRecoveryIsConsumed(` (17604)
- `(requireExactStartupEpisode || manualSourceSwitchSnapshot != null)` (18486)
- `result["startupSourcesExhausted"] = true` (16956)
- `"sourcePersistenceSessionId" to sourcePersistenceSessionId` (6 sites)
- `payloadCheck.optInt("sourcePersistenceSessionId", sourcePersistenceSessionId)` (2088)

`_between` ranges:

| Range (start → end) | Asserted content |
|---|---|
| `private fun onStremioSourceSelected(` [17944] → `private fun resolveStremioSourceViaFlutter(` [18003] | contains `maxAttempts = 1` |
| `private fun failManualSourceCandidate(` [17367] → `private fun armStartupCandidate(` [17431] | contains `manualSourceRestoreInProgress = true`, `playItem(currentIndex, suppressTrakt = true)`, `putAll(snapshot.perItemImdbIds)`, `This source is unavailable — choose another source`. Must NOT contain `nextIndex(` or `onStremioSourceSelected(` |
| `private fun resolveAndPlay(` [4649] → `private fun startPlayback(` [4754] | contains `reason=stale_manual_token`, `failManualSourceCandidate("initial-resolve")` |
| `private fun sendProgress(` [16801] → `private fun commitStartupCandidate(` [17497] | contains `manualSourceSwitchSnapshot != null`, `manualSourceRestoreInProgress`. This range spans ~700 lines: sendProgress, sendFinished, episode fetch, failManual, armStartup and more |
| `private fun failStartupCandidate(` [17566] → `private fun failStartupResolution(` [17681] | must NOT contain `reportRejectedSource`; contains `startupSourcesExhausted = true` |

### C3. Size gate

- `dev/tool/file_size_baseline.txt:3` reads `22221 android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt`. The baseline is shrink-only and is updated with `check_file_sizes.py --update`.
- `check_file_sizes.py` has `LIMIT = 800` and covers `android/app/src/.+\.(kt|java)`. Every new extracted Kotlin file must be ≤800 lines.
- CI: `.github/workflows/checks.yml`.

---------------------------------------------------------------------------------------------------
## D. TorboxTvPlayerActivity.java (6,478 lines) — shared vs duplicated

**Shared helper files used by BOTH players.** Keep the APIs stable:
- tv/:
  - `SeekFeedbackManager`
  - `SubtitleControlsLiftController`, `SubtitleLinePickerController`, `SubtitlePanelController`, `SubtitleSyncOverlayController`
  - `SubtitleAutoSelection` (AddonSubtitleCandidate, EmbeddedSubtitleCandidate, chooseAutomaticSubtitle, audioAllowsAutomaticSubtitles, isUndeclaredHlsCaption, selectedAudioLanguage, SubtitleTrackReadiness)
  - `TvDisplayModeController` / `TvDisplayModeSelector` / `TvContentDisplayMatchMode`
  - `UnifiedMenuController`, `UnifiedMenuSections`
- audio/: `AudioEffectSession`, `NativeAudioRenderersFactory`, `NativeAudioRouting`
- profiles/: `NativePlayerPreferences`
- subtitle/: `StremioSubtitle`, `StremioSubtitleService`
- util/: `LanguageMapper`, `OffsetRenderersFactory`, `SubtitleCue`, `SubtitleCueCache`, `SubtitleFontManager`, `SubtitleSettings`
- MainActivity: `getAndroidTvPlayerChannel()` (Torbox has 9 call sites).

**Torbox-only:** `DebrifyTvPlayerStyle`. Torbox's methods are `analyticsHeartbeat`, `lookupDebrifyTvIdentity`, `lookupMovieImdb`, `requestChannelById`, `requestNextChannel`, and the shared `searchSubtitleCatalogs`.

**ATV-only tv/ helpers:**
- `DockFormatTags`, `TvControlsSkin`, `SourceQualityParser`, `SourceAddonPresentation`
- `TvSourceBadgeResult`, `TvSourceBadgeText`, `TvSourceBrowserController`
- `StartupFailoverCursor`, `ShowShuffle`, `SkipDbSegmentClient`, `SwitchedEpisodeTitle`, `SpeechFeatureTap`
- `ProtectedStreamHttp`, `VodHttpDataSource`, `RecordingDataSource`
- `IptvDeviceQuirks`, `IptvGuideStyle`, `IptvLiveRecovery`, `IptvRecordingController`, `IptvTuneDiagnostics`
- `PlaybackReturnHandoff`, `TvPlaybackRecoveryStore`, `NullableJsonString`
- `diagnostics.DiagnosticFileLog`, `subtitle.AddonSubtitleResult/Status/StremioAddon`, `util.SubtitleAligner/AlignResult/CueSpan`
- the recording package
- `BadgeArtworkSize`, `StreamBadgeSvg`, `TvStreamBadgeStrip` and `TvTrailerTexturePlayer` aren't referenced by either activity.

**Duplicated, not shared:**
- `SubtitleCatalogResult`: Kotlin private data class at ATV 20518, Java `private static final class` at Torbox 4790. Same "searchSubtitleCatalogs" flow, implemented twice.
- The external-subtitle download flow: Torbox comment at 496 says "Mirrors AndroidTvTorrentPlayerActivity".
- The back-press / overlay dismissal shape (`setupBackPressHandler`, `linePickerOverlay`, `syncOverlay` field names). It is identical in both because SubtitleSyncDismissTest reflects the same names on both classes.
- `.setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)` exists in both and is pinned by NativeAudioRoutingTest.
- `trackSelector` and `nightModeIndex` field names exist in both and are pinned by NativePlayerSettingsConsumptionTest.

Note: unifying these duplicates is out of scope for a behavior-preserving split; the duplicates are listed only for awareness.

## Phase 1 step 0

2026-10-07 — characterized the original `39c630303` before any production move.
The six-part dependency inventory above is retained unchanged. Step T is
`05dd8a9e9`; all production code, `pubspec.lock`, and ProGuard rules remain
byte-identical to the original. The activity blob is
`60dc82cba2b36f09a171c86dc92b0bb385c2ef64` (22,221 lines).

### Coverage and original run

- Added **38 tests**; reused the 4 existing header/progress tests and 4 late
  metadata merge tests. Reflection, private JVM names and constructor order
  are confined to `TvPlayerOriginalAccess.kt`; production visibility is unchanged.
- Models: JSON/map fields and absent/empty keys, protected-stream headers,
  quality/coverage/title/size/failure identity, payload order/navigation/header
  inheritance and thresholds, group lookup, subtitle catalog formatting,
  season labels, watched/rewatch/local/tracker display edges and live metadata merges.
- Adapters: all seven adapters, counts/view types, numeric season/episode and
  movie group ordering/filtering, missing→actual→missing recycling, bound text,
  visibility/status/fallbacks, click/long-click consumption and focus callbacks,
  remote Select and first-row Up target, skin callbacks, all guide styles.
- All four payload overloads cover empty, unknown, recognized and mixed lists;
  playlist progress accepts its marker anywhere, IPTV and Stremio guide accept
  only the first marker. Tests pin full versus partial text/scale/focus effects,
  hidden/unchanged active notifications, identity updates, DiffUtil moves/content
  changes/source identity, EPG freshness eligibility, snapshots, readiness and
  mutable list membership.
- Stremio progress posts use attached, measured RecyclerViews. Assertions first
  require a valid binding position and a positive measured track width; then
  verify clamping, recycled channel identity and removal/NO_POSITION guards.
- Ring: PAUSED looper and paused 16 ms frame clock with bounded advances, real
  animator seeks for deterministic frames after suite-wide vsync clock changes,
  1,800 ms duration, requested INFINITE via ShadowValueAnimator, repeated-start
  clock, stop/reset, detach cancellation, arcColor, copied Paint halo/dot
  snapshots (geometry, style, stroke, RGB and alpha). Legacy Paint exposes alpha
  separately from packed color; every Canvas drawCircle copies the Paint.

Clean original run: `junit/p1-step0-original-verified/identities.json` at
`39c630303`, 11 dirty test files, JBR 21.0.10, **297 identities: 296 pass,
1 pre-existing failure, 0 skips**. The failed identity is still
`com.debrify.app.tv.TvSourceBrowserFocusTest::dpadAndRailFocusKeepRowsAndImportedArtworkAttached`.
Comparison against `baseline-39c630303` passes: all 259 baseline identities
remain with unchanged statuses; the only 38 additions pass. Input fingerprints
are equal before/after the run. Initial test-harness calibration logs are kept
in evidence; their failures were resolved before the verified run.

Post-step-0 phase baseline: `junit/p1-step0/identities.json` at
`05dd8a9e9`, 12 dirty files (tests + this report), JBR 21.0.10: **297 identities,
296 pass, the same single known failure, 0 skips**. The run completed with
equal before/after tree fingerprints. Both comparisons pass: against
`baseline-39c630303` (exactly 38 passing additions; no removals/status changes)
and against the verified original run (identical test identities/statuses).
Later phase-1 JVM runs must compare against `p1-step0`.

The facade-reference search over Kotlin, Java, Dart tests and ProGuard files
found no explicit `AndroidTvTorrentPlayerActivityKt` or `TvPlaybackItemKt`
references (exit 1 / no matches); `p1/facade-reference-search.log` records the
command. Existing direct internal merge-helper tests retain their assertions.

### Original-code mutation table

**49 isolated mutations / 46 named tests**, including every new test and each
reused header/progress/merge test. Each row ran exactly one named test against
`39c630303` plus the test files and one original-code mutation. Each compiled
and failed with `java.lang.AssertionError` or `org.junit.ComparisonFailure`;
no compile failure/crash qualifies. Ring duration/repeat/start and stop/detach
have separate proofs. The NO_POSITION mutation clamps an invalid position to
zero, exercising the forbidden update without producing an indexing crash.

All paths below are relative to `<git-common-dir>/refactor-evidence/tvplayer/`.
`p1/mutations/<ID>/` contains `mutation.patch`, `gradle.log`, and raw `xml/`.
`p1/mutations.json` pins exact PSI owner, offsets and before/after text;
`p1/mutation-results.json` records the assertion and stack for every run;
`p1/run_mutations.py` reproduces one-at-a-time application and assertion checks.
`p1/step0-test-inputs/` and `p1/step0-summary.json` archive inputs and hashes.
The detached evidence worktree is removed after the proofs.

| ID | Named test | Original mutation (before → after) | Failing assertion |
| --- | --- | --- | --- |
| 01-allLaunchFieldsMapWithoutLosingOptionalValues | `PlaybackItemHeadersTest.allLaunchFieldsMapWithoutLosingOptionalValues` | `id = obj.optString("id")` → `id = "mutated"` | `org.junit.ComparisonFailure: expected:<[i]d> but was:<[mutate]d>` |
| 02-absentAndEmptyLaunchKeysKeepOriginalDefaults | `PlaybackItemHeadersTest.absentAndEmptyLaunchKeysKeepOriginalDefaults` | `index = obj.optInt("index", 0)` → `index = obj.optInt("index", 1)` | `java.lang.AssertionError: expected:<0> but was:<1>` |
| 03-watchedAndRewatchEdgesKeepTheOriginalDisplayPolicy | `PlaybackProgressPolicyTest.watchedAndRewatchEdgesKeepTheOriginalDisplayPolicy` | `if (watched) return 100` → `if (watched) return 99` | `java.lang.AssertionError: expected:<100> but was:<99>` |
| 04-sourceJsonAndMapKeepFieldsQualityAndFailureIdentity | `TvPlayerModelCharacterizationTest.sourceJsonAndMapKeepFieldsQualityAndFailureIdentity` | `seeders = obj.optInt("seeders", 0)` → `seeders = obj.optInt("seeders", 0) + 1` | `java.lang.AssertionError: expected:<8> but was:<9>` |
| 05-sourceAbsentKeysAndDisplayFallbacksRemainDistinct | `TvPlayerModelCharacterizationTest.sourceAbsentKeysAndDisplayFallbacksRemainDistinct` | `?: "HD"` → `?: "SD"` | `org.junit.ComparisonFailure: expected:<[H]D> but was:<[S]D>` |
| 06-payloadParsingKeepsOrderNavigationHeadersAndClampedThresholds | `TvPlayerModelCharacterizationTest.payloadParsingKeepsOrderNavigationHeadersAndClampedThresholds` | `val startIndex = obj.optInt("startIndex", 0).coerceIn(0, items.lastIndex.coerceAtLeast(0))` → `val startIndex = 0` | `java.lang.AssertionError: expected:<1> but was:<0>` |
| 07-groupLookupAndSubtitleCatalogFormattingKeepOriginalOrder | `TvPlayerModelCharacterizationTest.groupLookupAndSubtitleCatalogFormattingKeepOriginalOrder` | `"$name ($year)"` → `"$name [$year]"` | `org.junit.ComparisonFailure: expected:<Show [(2024)]> but was:<Show [[2024]]>` |
| 08-seasonsGuideUnionAndFilteringKeepNumericEpisodeOrder | `TvPlaylistAdapterCharacterizationTest.seasonsGuideUnionAndFilteringKeepNumericEpisodeOrder` | `(grouped.keys + guideGrouped.keys).distinct().sorted()` → `(grouped.keys + guideGrouped.keys).distinct().sortedDescending()` | `java.lang.AssertionError: expected:<[0, 1, 0, 1, 1, 1]> but was:<[0, 1, 1, 1, 0, 1]>` |
| 09-missingAndActualRebindResetDimmingAndClickOwnership | `TvPlaylistAdapterCharacterizationTest.missingAndActualRebindResetDimmingAndClickOwnership` | `itemView.alpha = 0.55f` → `itemView.alpha = 0.65f` | `java.lang.AssertionError: expected:<0.55> but was:<0.65>` |
| 10-episodeBindKeepsWatchedProgressFallbackAndClassicFocus | `TvPlaylistAdapterCharacterizationTest.episodeBindKeepsWatchedProgressFallbackAndClassicFocus` | `progressText.text = "${progressPercent}%"` → `progressText.text = "${progressPercent}x"` | `org.junit.ComparisonFailure: expected:<40[%]> but was:<40[x]>` |
| 11-skinBinderAndFocusedItemUseTheCurrentOriginalIndex | `TvPlaylistAdapterCharacterizationTest.skinBinderAndFocusedItemUseTheCurrentOriginalIndex` | `onItemFocused.invoke(item, lastBoundIndex)` → `onItemFocused.invoke(item, lastBoundIndex + 1)` | `Focused callback index: expected 1, got 2 (same item).` |
| 12-progressPayloadAnywherePreservesTitleButUnknownAndEmptyFullyBind | `TvPlaylistAdapterCharacterizationTest.progressPayloadAnywherePreservesTitleButUnknownAndEmptyFullyBind` | `PAYLOAD_PROGRESS_UPDATE !in payloads` → `payloads.firstOrNull() != PAYLOAD_PROGRESS_UPDATE` | `org.junit.ComparisonFailure: expected:<[Before]> but was:<[After]>` |
| 13-activeAndProgressNotificationsRespectHiddenAndUnchangedPositions | `TvPlaylistAdapterCharacterizationTest.activeAndProgressNotificationsRespectHiddenAndUnchangedPositions` | `if (previousActivePosition != -1)` → `if (false)` | `Unchanged active position: expected two full changes plus progress; got one full change plus progress.` |
| 14-groupOrderAndForceRefreshKeepHiddenActiveItems | `TvMovieAdapterCharacterizationTest.groupOrderAndForceRefreshKeepHiddenActiveItems` | `visibleIndices.addAll(currentGroup.fileIndices)` → `visibleIndices.addAll(currentGroup.fileIndices.reversed())` | `java.lang.AssertionError: expected:<[Two, Zero]> but was:<[Zero, Two]>` |
| 15-movieBindKeepsFallbackStatusClickAndClassicFocus | `TvMovieAdapterCharacterizationTest.movieBindKeepsFallbackStatusClickAndClassicFocus` | `0.4f else 1.0f` → `0.5f else 1.0f` | `java.lang.AssertionError: expected:<0.4> but was:<0.5>` |
| 16-moviePayloadMatrixAndSkinFocusKeepFullBindSeparate | `TvMovieAdapterCharacterizationTest.moviePayloadMatrixAndSkinFocusKeepFullBindSeparate` | `PAYLOAD_PROGRESS_UPDATE !in payloads` → `payloads.firstOrNull() != PAYLOAD_PROGRESS_UPDATE` | `org.junit.ComparisonFailure: expected:<[Before]> but was:<[After]>` |
| 17-movieActiveNotificationsKeepDuplicateAndHiddenSemantics | `TvMovieAdapterCharacterizationTest.movieActiveNotificationsKeepDuplicateAndHiddenSemantics` | `if (previousPosition != -1)` → `if (false)` | `Unchanged active position: expected two full changes plus progress; got one full change plus progress.` |
| 18-channelClassicRowsKeepBadgesFallbackClickLongClickAndFocus | `TvIptvAdapterCharacterizationTest.channelClassicRowsKeepBadgesFallbackClickLongClickAndFocus` | `(entry.channelNumber ?: (entry.index + 1)).toString()` → `(entry.channelNumber ?: (entry.index + 1)).plus(1).toString()` | `org.junit.ComparisonFailure: expected:<[7]> but was:<[8]>` |
| 19-channelStylesKeepConsoleNumbersAndEditionColors | `TvIptvAdapterCharacterizationTest.channelStylesKeepConsoleNumbersAndEditionColors` | `displayNumber.padStart(3, '0')` → `displayNumber.padStart(4, '0')` | `org.junit.ComparisonFailure: expected:<00[]7> but was:<00[0]7>` |
| 20-epgPayloadOnlyInFirstSlotPreservesFocusScaleAndName | `TvIptvAdapterCharacterizationTest.epgPayloadOnlyInFirstSlotPreservesFocusScaleAndName` | `payloads[0] == PAYLOAD_EPG` → `PAYLOAD_EPG in payloads` | `org.junit.ComparisonFailure: expected:<[After]> but was:<[Before]>` |
| 21-staleEpgRequestsOnlyEligibleLiveRowsAndSnapshotsStayIndependent | `TvIptvAdapterCharacterizationTest.staleEpgRequestsOnlyEligibleLiveRowsAndSnapshotsStayIndependent` | `if (!entry.epgLoaded \|\| stale)` → `if (!entry.epgLoaded)` | `EPG callbacks: expected both unfetched and stale rows; got only unfetched.` |
| 22-identityNotificationsRejectEqualCopiesAndAvoidDuplicateCurrentUpdates | `TvIptvAdapterCharacterizationTest.identityNotificationsRejectEqualCopiesAndAvoidDuplicateCurrentUpdates` | `it === entry` → `it == entry` | `assertTrue(events.isEmpty()) — an equal copy incorrectly notified.` |
| 23-diffUpdatesDistinguishContentsIdentityMovesAndAliasedInput | `TvIptvAdapterCharacterizationTest.diffUpdatesDistinguishContentsIdentityMovesAndAliasedInput` | `before.sourceId == after.sourceId` → `true` | `assertTrue(events.any { it.kind == "remove" }) — source identity was incorrectly reused.` |
| 24-categoryOrderSelectionRemoteClickAndFirstRowFocusTarget | `TvIptvPickerAndEpgCharacterizationTest.categoryOrderSelectionRemoteClickAndFirstRowFocusTarget` | `selectedCategory ?: "All categories"` → `selectedCategory ?: "Movies"` | `assertTrue(first.itemView.isSelected) — default category no longer selected.` |
| 25-listReadinessAndMutableMembershipControlCheckedRowsAndNotifications | `TvIptvPickerAndEpgCharacterizationTest.listReadinessAndMutableMembershipControlCheckedRowsAndNotifications` | `if (ready) lists.size else 0` → `lists.size` | `java.lang.AssertionError: expected:<0> but was:<1>` |
| 26-epgTimeStatesReplayAndFutureRecordingUseTheBoundProgram | `TvIptvPickerAndEpgCharacterizationTest.epgTimeStatesReplayAndFutureRecordingUseTheBoundProgram` | `"START OVER"` → `"START AGAIN"` | `org.junit.ComparisonFailure: expected:<START [OVER]> but was:<START [AGAIN]>` |
| 27-styledEpgRecyclingClearsSelectedWhileClassicKeepsItsExistingState | `TvIptvPickerAndEpgCharacterizationTest.styledEpgRecyclingClearsSelectedWhileClassicKeepsItsExistingState` | `holder.itemView.isSelected = airing` → `holder.itemView.isSelected = !airing` | `java.lang.AssertionError: expected:<true> but was:<false>` |
| 28-guideRowsKeepCurrentFallbackNowNextClickAndFocus | `TvStremioGuideCharacterizationTest.guideRowsKeepCurrentFallbackNowNextClickAndFocus` | `"Next: ${channel.nextUpTitle}"` → `"Later: ${channel.nextUpTitle}"` | `org.junit.ComparisonFailure: expected:<[Next]: Next Film (2025)> but was:<[Later]: Next Film (2025)>` |
| 29-switchingLoadingAndEmptyDataClearTheRecycledGuideRow | `TvStremioGuideCharacterizationTest.switchingLoadingAndEmptyDataClearTheRecycledGuideRow` | `"Tuning..."` → `"Switching..."` | `org.junit.ComparisonFailure: expected:<[Tun]ing...> but was:<[Switch]ing...>` |
| 30-guidePayloadFirstSlotMatrixPreservesStaticFieldsAndScale | `TvStremioGuideCharacterizationTest.guidePayloadFirstSlotMatrixPreservesStaticFieldsAndScale` | `val payload = payloads[0]` → `val payload = payloads.firstOrNull { it == PAYLOAD_GUIDE_DATA \|\| it == PAYLOAD_SWITCH_STATE }` | `org.junit.ComparisonFailure: expected:<[After]> but was:<[Before]>` |
| 31-attachedMeasuredHolderAppliesClampedPostedProgressWidth | `TvStremioGuideCharacterizationTest.attachedMeasuredHolderAppliesClampedPostedProgressWidth` | `coerceIn(0f, 1f)` → `coerceIn(0f, 0.5f)` | `java.lang.AssertionError: expected:<846> but was:<423>` |
| 32-postedProgressRejectsAReboundChannelAtTheSameAttachedPosition | `TvStremioGuideCharacterizationTest.postedProgressRejectsAReboundChannelAtTheSameAttachedPosition` | `if (currentChannel.id != channelId) return@post` → `// mutation: allow a stale channel id` | `java.lang.AssertionError: expected:<17> but was:<211>` |
| 33-postedProgressRejectsNoPositionAfterAnAttachedHolderIsRemoved | `TvStremioGuideCharacterizationTest.postedProgressRejectsNoPositionAfterAnAttachedHolderIsRemoved` | `val pos = holder.bindingAdapterPosition` → `val pos = holder.bindingAdapterPosition.coerceAtLeast(0)` | `java.lang.AssertionError: expected:<19> but was:<211>` |
| 34-guideUpdatesKeepIdLookupsCurrentFallbackAndNotifications | `TvStremioGuideCharacterizationTest.guideUpdatesKeepIdLookupsCurrentFallbackAndNotifications` | `it.id == id` → `it.id != id` | `java.lang.AssertionError: expected:<1> but was:<0>` |
| 35-ring-duration | `TvAutoSyncRingCharacterizationTest.pulseDurationRepeatRequestAndRepeatedStartKeepTheSameClock` | `duration = 1_800` → `duration = 1_801` | `java.lang.AssertionError: expected:<1800> but was:<1801>` |
| 36-ring-stop-reset | `TvAutoSyncRingCharacterizationTest.stopResetsPulseAndDetachCancelsTheOwnedAnimator` | `pulse = 0f` → `pulse = 0.5f` | `java.lang.AssertionError: expected:<0.0> but was:<0.5>` |
| 37-ring-halo-alpha | `TvAutoSyncRingCharacterizationTest.haloAlphaAndArcColorAreSnapshotsBeforePaintReset` | `(82 * (1f - pulse))` → `(80 * (1f - pulse))` | `java.lang.AssertionError: expected:<41> but was:<40>` |
| 38-ring-halo-stroke | `TvAutoSyncRingCharacterizationTest.haloStrokeGeometryAndSolidDotKeepIndependentPaintSnapshots` | `w * 0.14f` → `w * 0.12f` | `java.lang.AssertionError: expected:<14.0> but was:<12.0>` |
| 39-ring-infinite-request | `TvAutoSyncRingCharacterizationTest.pulseDurationRepeatRequestAndRepeatedStartKeepTheSameClock` | `repeatCount = ValueAnimator.INFINITE` → `repeatCount = 0` | `java.lang.AssertionError: expected:<-1> but was:<0>` |
| 40-ring-repeated-start | `TvAutoSyncRingCharacterizationTest.pulseDurationRepeatRequestAndRepeatedStartKeepTheSameClock` | `if (!pulseAnimator.isStarted) pulseAnimator.start()` → `pulseAnimator.start()` | `java.lang.AssertionError: expected:<900> but was:<0>` |
| 41-ring-detach | `TvAutoSyncRingCharacterizationTest.stopResetsPulseAndDetachCancelsTheOwnedAnimator` | `pulseAnimator.cancel()` → `// mutation: leave animator started` | `assertFalse(animator.isStarted) after detach — animator remained started.` |
| 42-methodChannelReplacementPreservesNativeMapHeaders | `PlaybackItemHeadersTest.methodChannelReplacementPreservesNativeMapHeaders` | `httpHeaders = ProtectedStreamHttp.headers(obj.opt("httpHeaders"))` → `httpHeaders = emptyMap()` | `java.lang.AssertionError: expected:<episode-2> but was:<null>` |
| 43-replacementWithoutHeadersDoesNotInheritLaunchCredentials | `PlaybackItemHeadersTest.replacementWithoutHeadersDoesNotInheritLaunchCredentials` | `httpHeaders = ProtectedStreamHttp.headers(obj.opt("httpHeaders"))` → `httpHeaders = emptyMap()` | `java.lang.AssertionError: expected:<Bearer original> but was:<null>` |
| 44-eachEpisodeRetainsItsHeadersAcrossMetadataAndUrlUpdates | `PlaybackItemHeadersTest.eachEpisodeRetainsItsHeadersAcrossMetadataAndUrlUpdates` | `httpHeaders = ProtectedStreamHttp.headers(obj.opt("httpHeaders"))` → `httpHeaders = emptyMap()` | `java.lang.AssertionError: expected:<episode-1> but was:<null>` |
| 45-excludedLocalProgressDoesNotOverrideTracker | `PlaybackProgressPolicyTest.excludedLocalProgressDoesNotOverrideTracker` | `allowLocalProgressDisplay && durationMs > 0` → `durationMs > 0` | `java.lang.AssertionError: expected:<20> but was:<40>` |
| 46-currentRowNeverMovesBehindLivePlayback | `LateEpisodeMetadataMergeTest.currentRowNeverMovesBehindLivePlayback` | `maxOf(snapshotPositionMs, livePositionMs.coerceAtLeast(0L))` → `snapshotPositionMs` | `java.lang.AssertionError: expected:<42000> but was:<20000>` |
| 47-currentRowCanAdoptFurtherCrossDeviceProgress | `LateEpisodeMetadataMergeTest.currentRowCanAdoptFurtherCrossDeviceProgress` | `maxOf(snapshotPositionMs, livePositionMs.coerceAtLeast(0L))` → `livePositionMs` | `java.lang.AssertionError: expected:<60000> but was:<42000>` |
| 48-nonCurrentRowHonoursExplicitProgressClear | `LateEpisodeMetadataMergeTest.nonCurrentRowHonoursExplicitProgressClear` | `incomingPositionMs ?: existingPositionMs` → `incomingPositionMs?.takeIf { it > 0 } ?: existingPositionMs` | `java.lang.AssertionError: expected:<0> but was:<60000>` |
| 49-currentRowKeepsLiveDuration | `LateEpisodeMetadataMergeTest.currentRowKeepsLiveDuration` | `isCurrentItem && liveDurationMs > 0L` → `false` | `java.lang.AssertionError: expected:<3100000> but was:<0>` |
### Retargets and remaining review

No anchors or reflection consumers have moved in step 0. Existing behavioural
assertions are preserved. Step 1 must retarget only the original-access helper
and the previously inventoried Dart source anchors in the move commits.
Claude’s independent sampling of at least 10 additional mutations and any
resulting step 0b gaps remain for the independent reviewer. No device interaction
or production moves were performed. Release/R8/Dart suite phase gates remain
at their planned later milestone.


## Phase 1 step 0b

Closed all seven independent Claude survivors on **original `39c630303`**.
Added **26 tests**, strengthened the existing ring pulse test, and expanded
`TvPlayerOriginalAccess` only for the original Kotlin default constructor and
Glide's installed request listeners and a valid wrapped episode-holder
hierarchy separating row and descendant-container alpha. Production source, dependencies, lockfile,
and ProGuard rules were unchanged while establishing this baseline.

The final original characterization run is **72/72 passing** (all phase-1
characterizations plus `PlaybackItemHeadersTest`, `PlaybackProgressPolicyTest`,
and `LateEpisodeMetadataMergeTest`). Each new/strengthened named test below has
an original-code mutation ending in `AssertionError`/`ComparisonFailure`.
The zero-duration EPG case catches division errors and fails an assertion: its
observable contract is a successful bind for malformed/zero-length programmes.

Evidence resolves through `<git-common-dir>/refactor-evidence/tvplayer/`:
`p1/step0b/cases.json`, `results.json`, `mutations/<id>/mutation.patch`,
`gradle.log`, raw `xml/`; both initial/final test inputs and clean original
logs/XML are archived there. The proof runner verifies the original revision,
restores the original after each case, and checks the unchanged lockfile.

### New and strengthened test → mutation → failing assertion

| Named test | Original mutation | Failing assertion | Evidence ID |
|---|---|---|---|
| `TvAdapterFocusCharacterizationTest.classicEpisodeFocusUsesBothScaleAxesElevationAndDurations` | `?.scaleX(1.08f) \n                         ?.scaleY(1.08f)` → `?.scaleX(1.06f) \n                         ?.scaleY(1.08f)` | expected:<1.08> but was:<1.06> | `complete-c04` |
| `TvAdapterFocusCharacterizationTest.guideAndPickerFocusTargetsDurationsAndRowDimensionsStayExact` | `120` → `121` | expected:<120> but was:<121> | `n000` |
| `TvAdapterFocusCharacterizationTest.movieFocusUsesBothScaleAxesAndBothDurations` | `1.08f` → `1.13f` | expected:<1.08> but was:<1.13> | `n051` |
| `TvAdapterFocusCharacterizationTest.playingDotKeepsItsPulseValuesDurationRepeatAndStopReset` | `ObjectAnimator.ofFloat(dot, "alpha", 1f, 0.3f, 1f)` → `ObjectAnimator.ofFloat(dot, "alpha", 0.9f, 0.3f, 1f)` | expected:<1.0> but was:<0.9> | `x007` |
| `TvAdapterFocusCharacterizationTest.seasonHeaderZeroOneAndManyUseTheOriginalPluralRule` | `subtitleView.text = "$episodeCount Episode${if (episodeCount != 1) "s" else ""}"` → `subtitleView.text = "$episodeCount Episode${if (episodeCount > 1) "s" else ""}"` | expected:<0 Episode[s]> but was:<0 Episode[]> | `complete-c01` |
| `TvArtworkVisibilityCharacterizationTest.channelLogoStartFailureAndSuccessKeepTheOriginalListenerConsumption` | `View.GONE` → `View.INVISIBLE` | expected:<8> but was:<4> | `v054` |
| `TvArtworkVisibilityCharacterizationTest.episodeArtworkLoadingFailureAndSuccessPinEveryVisibilityAssignment` | `View.GONE` → `View.INVISIBLE` | view=2131362147 expected:<8> but was:<4> | `v025` |
| `TvArtworkVisibilityCharacterizationTest.movieArtworkFailureAndSuccessUseGoneForTheReplacedView` | `View.GONE` → `View.INVISIBLE` | view=2131361893 expected:<8> but was:<4> | `v047` |
| `TvArtworkVisibilityCharacterizationTest.stremioPosterStartFailureAndSuccessKeepTheOriginalListenerConsumption` | `View.GONE` → `View.INVISIBLE` | expected:<8> but was:<4> | `v063` |
| `TvAutoSyncRingCharacterizationTest.haloAppearsAboveZeroAndExpandsToFullRadiusWithZeroAlphaAtOne` | `0f` → `0.05f` | expected:<2> but was:<1> | `n007` |
| `TvAutoSyncRingCharacterizationTest.pulseDurationRepeatRequestAndRepeatedStartKeepTheSameClock` | `ValueAnimator.ofFloat(0f, 1f)` → `ValueAnimator.ofFloat(0.1f, 1f)` | expected:<0.5> but was:<0.55> | `x005` |
| `TvAutoSyncRingCharacterizationTest.statusPaletteColorsKeepTheirOpaqueArgbValues` | `0xFF82E0AD` → `0xFE82E0AD` | expected:<-8200019> but was:<-24977235> | `x012` |
| `TvGuideVisibilityCharacterizationTest.epgAiringReplayFutureAndExpiredRowsPinVisibilityAlphaAndProgressScale` | `coerceAtLeast(1L)` → `coerceAtLeast(0L)` | EPG bind must handle a zero-duration programme: java.lang.ArithmeticException: / by zero | `x011` |
| `TvGuideVisibilityCharacterizationTest.iptvCurrentLiveFavoriteGroupAndEpgUseExactVisibleOrGoneStates` | `holder.favorite.visibility = if (entry.isFavorite) View.VISIBLE else View.GONE` → `holder.favorite.visibility = if (entry.isFavorite) View.VISIBLE else View.INVISIBLE` | favorite expected:<8> but was:<4> | `complete-c07` |
| `TvGuideVisibilityCharacterizationTest.stremioEndTimeUsesTwelveAtMidnightAndNoonAndGoneAtTheStopBoundary` | `val h12 = if (h == 0) 12 else h` → `val h12 = if (h == 0) 0 else h` | expected:<[12]:05 AM> but was:<[0]:05 AM> | `complete-c12` |
| `TvGuideVisibilityCharacterizationTest.stremioSwitchCurrentLoadingEmptyAndNextRowsPinEveryVisibilityAndTextAlpha` | `1.0f` → `1.05f` | expected:<1.0> but was:<1.05> | `final-n077` |
| `TvModelDefaultsCharacterizationTest.everyAbsentPlaybackKeyKeepsItsJsonAndMapDefault` | `val mimeType: String? = null` → `val mimeType: String? = "changed"` | PlaybackItem equality; absent mimeType must keep its explicit expected default | `mime-default` |
| `TvModelDefaultsCharacterizationTest.everyAbsentSourceKeyKeepsItsJsonAndMapDefault` | `seeders = obj.optInt("seeders", 0)` → `seeders = obj.optInt("seeders", 1)` | JSON.seeders expected:<0> but was:<1> | `complete-c14` |
| `TvModelDefaultsCharacterizationTest.lateMetadataPositiveDurationAndNegativeLivePositionBoundsStayExact` | `liveDurationMs > 0L` → `liveDurationMs > 1L` | expected:<1> but was:<30000> | `x002` |
| `TvModelDefaultsCharacterizationTest.payloadConstructorDefaultsKeepCompletionThresholdsAndIndependentGuideLists` | `movieCompletionThreshold: Int = 80` → `movieCompletionThreshold: Int = 81` | expected:<80> but was:<81> | `x000` |
| `TvModelDefaultsCharacterizationTest.rewatchBoundariesDistinguishNinetyNinetyFourAndNinetyFive` | `if (allowLocalProgressDisplay && trakt >= 95 && resumePositionMs > 0 && local < 95) return local` → `if (allowLocalProgressDisplay && trakt >= 95 && resumePositionMs > 0 && local < 90) return local` | local=90 tracker=95 expected:<90> but was:<95> | `complete-c19` |
| `TvModelDefaultsCharacterizationTest.sourceDisplayTitleAndSizeBoundaryLiteralsRemainObservable` | `newlineIdx <= 0` → `newlineIdx <= 1` | expected:<[]Movie> but was:<[A \n ]Movie> | `x010` |
| `TvPlaylistThresholdCharacterizationTest.episodeFullAndPartialBindsPinProgressThresholdsAlphaAndExactVisibility` | `95` → `94` | view=2131361898 expected:<0> but was:<8> | `r-n043` |
| `TvPlaylistThresholdCharacterizationTest.episodeMetadataZeroBoundariesBadgePaddingAndFallbackStatesStayExact` | `View.GONE` → `View.INVISIBLE` | view=2131361891 expected:<8> but was:<4> | `v000` |
| `TvPlaylistThresholdCharacterizationTest.missingToActualBindResetsRootAndContainerAlphaIndependently` | `1.0f` → `1.05f` | expected:<1.0> but was:<1.05> | `final-n024` |
| `TvPlaylistThresholdCharacterizationTest.movieFullAndPartialBindsPinProgressThresholdsAlphaAndExactVisibility` | `94` → `93` | view=2131361897 expected:<0> but was:<8> | `r-n063` |
| `TvPlaylistThresholdCharacterizationTest.movieSizeBoundariesGroupColorsAndAttachedFallbackNumberStayExact` | `View.GONE` → `View.INVISIBLE` | view=2131361891 expected:<8> but was:<4> | `v035` |

### Claude's seven exact survivors re-run on the final tests

Every final re-run executes **all 72 relevant tests**; no compilation error or
crash supplies the proof. Raw patches preserve Claude's exact before/after
strings, including the original 90% rewatch mutation.

| Named test | Exact original mutation | Failing assertion | Evidence ID |
|---|---|---|---|
| `TvAdapterFocusCharacterizationTest.seasonHeaderZeroOneAndManyUseTheOriginalPluralRule` | `subtitleView.text = "$episodeCount Episode${if (episodeCount != 1) "s" else ""}"` → `subtitleView.text = "$episodeCount Episode${if (episodeCount > 1) "s" else ""}"` | expected:<0 Episode[s]> but was:<0 Episode[]> | `complete-c01` |
| `TvAdapterFocusCharacterizationTest.classicEpisodeFocusUsesBothScaleAxesElevationAndDurations` | `?.scaleX(1.08f) \n                         ?.scaleY(1.08f)` → `?.scaleX(1.06f) \n                         ?.scaleY(1.08f)` | expected:<1.08> but was:<1.06> | `complete-c04` |
| `TvGuideVisibilityCharacterizationTest.iptvCurrentLiveFavoriteGroupAndEpgUseExactVisibleOrGoneStates` | `holder.favorite.visibility = if (entry.isFavorite) View.VISIBLE else View.GONE` → `holder.favorite.visibility = if (entry.isFavorite) View.VISIBLE else View.INVISIBLE` | favorite expected:<8> but was:<4> | `complete-c07` |
| `TvGuideVisibilityCharacterizationTest.iptvCurrentLiveFavoriteGroupAndEpgUseExactVisibleOrGoneStates` | `holder.liveBadge.visibility = if (entry.isLive) View.VISIBLE else View.GONE` → `holder.liveBadge.visibility = View.GONE` | liveBadge expected:<0> but was:<8> | `complete-c08` |
| `TvGuideVisibilityCharacterizationTest.stremioEndTimeUsesTwelveAtMidnightAndNoonAndGoneAtTheStopBoundary` | `val h12 = if (h == 0) 12 else h` → `val h12 = if (h == 0) 0 else h` | expected:<[12]:05 AM> but was:<[0]:05 AM> | `complete-c12` |
| `TvModelDefaultsCharacterizationTest.everyAbsentSourceKeyKeepsItsJsonAndMapDefault` | `seeders = obj.optInt("seeders", 0)` → `seeders = obj.optInt("seeders", 1)` | JSON.seeders expected:<0> but was:<1> | `complete-c14` |
| `TvModelDefaultsCharacterizationTest.rewatchBoundariesDistinguishNinetyNinetyFourAndNinetyFive` | `if (allowLocalProgressDisplay && trakt >= 95 && resumePositionMs > 0 && local < 95) return local` → `if (allowLocalProgressDisplay && trakt >= 95 && resumePositionMs > 0 && local < 90) return local` | local=90 tracker=95 expected:<90> but was:<95> | `complete-c19` |

### Gap-class sweep and equivalent mutations

The sweep has **278 distinct mutation archives**, **262 assertion-killed
runs**, 14 equivalent variants, and two early survivors killed after
strengthening: Stremio Y-reset (`final-n077`) and independent row/container
alpha reset (`final-n024`). It covers all
**74 `View.GONE` sites** in moved adapters, all **35 explicit/implicit
`optX` default sites**, six explicit map fallbacks, guarded absent defaults,
optional map/JSON fields, constructor defaults, focus scales on both axes,
elevations and durations, watched/progress bounds in full and partial binds,
text alpha values, size/title boundaries, ring/dot endpoints and geometry.
`numeric-inventory.json` records all 302 PSI numeric tokens, including literals
that are parameters, ordinal indexes, colours, or unreachable code. Absent
`PlaybackItem` expected values are all explicit, avoiding dependence on the
constructor defaults being characterized. Source defaults pin all 19 fields;
playback defaults pin all 23 fields on JSON and map paths.

The following variants are not behaviour changes and cannot supply a behaviour
proof; the exact move checker preserves their original tokens anyway:

- `v026`, `v027`, `v030`, `v031`: poster/shimmer hiding immediately repeated by
  `showFallback`. Terminal poster/shimmer states are asserted and their setters
  are individually killed elsewhere in the sweep.
- `d017`, `d018`, `d022`, `d023`, `d027`, `d030`: guarded string `optString`
  fallbacks never supply an absent value; `obj.has` selects `null` first.
  Android SDK-28 `JSONObject.optString`/`JSON.toString` bytecode is archived:
  present JSON NULL becomes the string "null", not the fallback. The actual
  absent-result branches are killed separately (`g000`–`g010`).
- `n043`, `n046`, `n063`, `n064`: raising the upper progress bound admits only
  rows already excluded by the watched guard. Lowering each bound is observable
  at 94%, and is assertion-killed in `r-n043`, `r-n046`, `r-n063`, `r-n064`.

Private `getSeasonGradient` has no production caller; its literals are retained
verbatim rather than tested through an invented caller. Constructor thresholds,
actual focus/pulse endpoints, mutable-list ownership, positive one-millisecond
bounds, rating zero boundaries, and midnight/noon labels are covered. No bugs
were fixed. Calibration attempts are retained separately under `calibration-1/`
and are excluded from accepted evidence. Robolectric's fresh Paint alpha is a
legacy-shadow artifact: palette opacity is checked from packed ARGB; halo/dot
alpha snapshots after pulsing draws remain independently asserted.

Clean JVM baseline: **`junit/p1-step0b`**, 323 identities (322 pass, the same
known focus failure, zero skips). Comparison with `p1-step0`: **26 passing
additions only**, all 297 prior identities and statuses retained. Tested HEAD
`739f9992d`, 8 dirty files, JBR 21.0.10; input fingerprints match before/after.
The original detached worktree was removed after archiving the proofs.


## Phase 1 step 1 — production moves and retargets

All 29 planned subtrees now live in the ten manifest destinations in
`com.debrify.app.tv`. The exhaustive PSI check classifies 3,477 declarations
with zero differences, including retained bodies, comments, newlines, order
and frozen activity imports. Only declared visibility changes and ring
`inner` removal occur. Existing activity callers resolve the moved package
types directly; the ring uses the same Context with no outer capture.

| Original test anchor | New anchor | Assertion preservation |
|---|---|---|
| `AndroidTvTorrentPlayerActivity$IptvCategoryAdapter` | `IptvCategoryAdapter` | Helper binary-name lookup only; all behavior assertions unchanged. |
| `AndroidTvTorrentPlayerActivity$IptvListPickerAdapter` | `IptvListPickerAdapter` | Helper binary-name lookup only; all behavior assertions unchanged. |
| `AndroidTvTorrentPlayerActivity$AutoSyncColors` | `AutoSyncColors` | Helper binary-name lookup only; all palette assertions unchanged. |
| `AndroidTvTorrentPlayerActivity$AutoSyncRingView(outer, Context)` | `AutoSyncRingView(Context)` | Helper constructor lookup only; test-facing helper signature and all timing/draw/lifetime assertions unchanged. |
| MDBList source test: synthetic `PlaybackItem` through `bindMissing`, Activity file | Same range in `TvPlaylistAdapter.kt` | All four serialized resume/duration/tracker/watched assertions unchanged. |
| MDBList source test: `if (watched) return 100`, Activity file | Same assertion in `TvPlaybackItem.kt` | Metadata handler assertions stay anchored to Activity; watched pin reads its new owner. |

All other listed reflection/source anchors remain in the activity: startup
watchdog, shuffle attempt, subtitle dismiss, native settings/rejected launch,
Dart auto-advance/manual validation/profile scan and native audio-routing
source reads. No explicit JVM facade-name consumers exist; normal Kotlin
references to the two merge functions resolve `TvPlaybackItemKt`.

Existing broad R8 keep rule at `proguard-rules.pro:52` is unchanged and covers
all package types and facades. Gate verification inventories release bytecode
for all ten destination SourceFile attributes, including generated nested
holders/companions/lambdas, and checks every class/field/method identity in
the release mapping.

The size ratchet was lowered with `--update`, scoped to the activity entry;
unrelated pre-existing shrinkage entries were restored to avoid scope growth.
All destinations are below 800 lines. Remaining activity responsibilities
retain the documented phases 2–7 exit milestones. Existing native English
labels are preserved as a legacy localization exception: native controls need
a scoped localization prerequisite in a separate migration.


## Phase 1 gate evidence

Checked source revision `b783e5b02`. Clean JVM `p1-gate` equals `p1-step0b`:
323 identities, 322 passing, one unchanged focus failure, no skips/additions/
missing identities; stable inputs. Kotlin compile succeeds with exactly the
same five warning messages. Exhaustive checker: 3,477 declarations, zero
differences; 24 self-tests pass; size and changed-Dart formatting pass. Analyzer
adds zero diagnostics. Focused source-anchor run: 44 pass and the unchanged
profile-source guard failure; the verified rerun has stable fingerprints.

`flutter build apk --release` succeeds (102.2 MB). Complete rule-5 coverage
uses release Kotlin SourceFile attributes to enumerate all ten destinations:
**53 classes, 1,080 fields/methods**, including holders, companions, anonymous
classes and `TvPlaybackItemKt`. Every class has an explicit identity mapping.
R8 emits **519 explicit member mappings**, and omits **561 unchanged member
identities** from its text output. All 1,080 original names and mapped type
descriptors are independently present as definitions in the APK DEX files;
no missing/renamed member is accepted. Mapping inline frames are grouped to
the residual declaration, avoiding false renames from caller frames. Three
negative controls reject a changed class mapping, changed member mapping and
a missing DEX member. Evidence: `p1/check_mapping.py`, `mapping-result.json`,
`moved-bytecode-inventory.json`, archived mapping/configuration/seeds/usage
and `release-provenance.json` (APK/input hashes). Rules are unchanged.

**Decoder gate failed; phase gate remains pending.** The verifier finds nine
missing required decoders and three missing auto-sync filters in each of the
three APK ABIs. APK `libmpv.so` bytes exactly equal the local pinned upstream
v1.1.5 fallback jars (MD5/SHA-256 recorded); the patched build marker is absent.
The existing CI patched-library recipe requires Linux. Vendored recipe, patch,
verification script, app Gradle settings, lockfile and ProGuard are byte-identical
to `39c630303` (`release-build-inputs-parity.json`). No binary substitution,
dependency/build-setting edit or bug fix was made. Evidence:
`decoder-verification.log`, `decoder-provenance.json`,
`decoder-missing-all-abis.json`; tracked Follow-up in the plan.

Full Flutter comparison against the observed original-source run passes with
**12,855 identical identities/statuses**: 12,794 pass, 13 failures, 28 errors,
20 skips. No added/missing/fixed/failed/skipped identity. Same Flutter 3.44.8 /
Dart 3.12.2; the tested tree stayed stable. Reporter emits one duplicate
success event, which the identity comparison correctly deduplicates. Evidence:
`flutter-gate.jsonl`, `.env.json`, `flutter-gate-comparison.log`,
`flutter-gate-identity-delta.json`, `flutter-gate-known-failures.json`.

The first concurrent source-anchor run changed its untracked-path fingerprint
when release compilation created a generated Kotlin session artifact;
it was rejected. The session file was archived/removed, and the source tests
were rerun after release build (`flutter-source-anchors-verified*`). Original
raw calibration and first mapping-parser attempt are retained, not counted
as passing evidence. No device, emulator, install or push occurred.

Independent post-review: **No P1s / no production-source regression**. Review
accepted complete mapping/DEX verification and independently matched all
mutation patches/XML, named proof coverage and gate comparisons. Required
decoder verification remains a P2 environment prerequisite; explicit repaint
coverage is a P3 follow-up before phase 3. Neither is represented as a passing
gate. Review and independent audit evidence: `p1/post-review/`.

---

## Phase 2 inventory (pure members, at `dcbd9aafe`)

> Scope note (plan, phase 2 design round 1): the selected phase-2 scope is the ≈900-line set in the plan. Statements below that assign the request functions to a phase-2 bridge *seam*, or propose parameterizing almost-pure functions in phase 2, are superseded: the request functions move verbatim as top-level functions, the seam and any parameterization come with later feature phases.


Source: `android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt` @ dcbd9aafe (19,961 lines; class 136–19961, companion 19914). Read-only survey.

### Method

1. Enumerated all 487 class-level `fun` declarations (4-space indent, class body before the companion) and brace-matched their spans on a string/comment-stripped copy of the file (no overlaps).
2. Collected every *bare* identifier in each span: not preceded by `.`, `?.`, `::` or `@`. Named-argument occurrences were dropped. Locals, params, lambda params, destructured vals, for-vars and local funs were excluded.
3. Flagged an identifier when it matches a class-level `val`/`var`/`fun`/nested type of the activity, `this`/`super`, or an Activity/Context API name (getString, resources, window, runOnUiThread, findViewById, currentFocus, cacheDir, filesDir, assets, …). A member is pure iff its flags are empty, or contain only names already in the pure set (fixpoint; every overload of a name must qualify).
4. **Manually re-read every candidate body in full** (all listed below), resolving each unqualified identifier.
   - Inherited Activity members are not hidden behind implicit receivers. `title` occurs only as a param, local or named argument.
   - All types used are top-level `internal` or public: PlaybackItem, PlaybackPayload, SeasonEpisode, SubtitleCatalogResult, IptvChannelEntry, IptvSourceEntry, IptvListEntry, IptvEpgProgram, StremioTvGuideChannel, UnifiedMenuController.Row, DiagnosticFileLog, MainActivity.
5. Checks:
   - **Collisions:** grepped every name across `android/app/src/main/kotlin/com/debrify/app/tv/*` and `android/app/src/main/java/com/debrify/app/tv/*`. Also checked activity imports with the same name, and star imports in the tv package (none). Same-named Java methods in TorboxTvPlayerActivity do not affect Kotlin resolution.
   - **Call forms:** looked for `this.name`, `this@X.name` and `::name` references (none).
   - **Declarations:** checked non-`private` modifiers and annotations on the declarations (all are plain `private fun` with no annotations; none is `@Volatile`, `@Synchronized` or an extension).
   - **Overloads:** no pure name has a non-pure overload left behind. The only multi-declaration name is `parseIptvChannels` ×2, and both overloads are pure.
6. **Tests:**
   - Kotlin JVM tests: `grep -rw NAME android/app/src/test` matched none of the names. Reflection goes through `TvPlayerOriginalAccess` with literal names, `ShufflePlaybackFlowTest` (`declaredClasses` → ShufflePlaybackAttempt) and `StremioTvStartupWatchdogTest` / `SubtitleSyncDismissTest` (fields plus `setupBackPressHandler`), and none of those target a candidate.
   - `NativeAudioRoutingTest` reads the activity source, but only for `setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)`.
   - Dart source-text tests: `test/manual_source_validation_contract_test.dart`, `test/android_tv_mdblist_progress_source_test.dart` and `test/android_tv_auto_advance_resume_test.dart`. Every string literal in them was matched against the candidate bodies (0 hits), and every `_between` anchor pair was resolved.
     - The only region containing candidates is `sendProgress(` → `commitStartupCandidate(` (16586–17282), which contains `requestQuickPlayNextEpisode` and `formatTime`. The region still exists after the move and its asserted strings (`manualSourceSwitchSnapshot != null`, `manualSourceRestoreInProgress`) are not in those bodies, so it is safe.
     - No anchor string is a candidate signature.

**Common to every move:** the functions become `internal fun` in package `com.debrify.app.tv` with an identical body; call sites stay unchanged.
- The activity's class-level `@OptIn(UnstableApi::class)` (androidx.annotation.OptIn, line 135) will no longer cover moved code. Superseded by the plan's corrected fixed set: exactly `languageOfOverride`, `buildAudioTrackLabel` and `IptvLiveLoadErrorPolicy` gain `@OptIn(UnstableApi::class)` (androidx.annotation.OptIn); step 0 re-derives the set from Media3 1.8.0 annotations; lint issue sets are compared, not used to decide.
- Each new file needs its own imports (Locale, JSONArray/JSONObject, Uri, MediaCodecList, Format, TrackSelectionOverride, PlaybackException, HttpDataSource, DiagnosticFileLog, MainActivity, MethodChannel are referenced unqualified or partly qualified in the bodies).
- `dev/tool/check_kotlin_moves.py` with a new manifest (`kotlin_moves/tvplayer_p2.json`) can prove the verbatim moves, as it did for phase 1.


### A. IPTV error classification + live-load policy → `IptvLoadErrorPolicy.kt`

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun classifyIptvError(error: PlaybackException): IptvLiveRecovery.ErrorClass` | 683–699 (fun@685) | 664(restoreAcceptedIptvTwinAfterAuth), 1937(class-body) | Pure. Media3 1.8.0 bytecode confirms all used APIs are stable; the corrected plan specifies **no opt-in** on this function. Caller 1937 is inside the anonymous Player.Listener. Original inventory had no tests/anchors; phase-2 characterization now covers it. |

**Group lines:** 17

### B. IPTV payload parsing → `IptvPayloadParsing.kt`

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun parseIptvSources(array: JSONArray?): MutableList<IptvSourceEntry>` | 8919–8937 | 8817(initIptvMode) | Pure (JSONArray/JSONObject + internal IptvSourceEntry). Tests/anchors: none. |
| `fun parseIptvLists(array: JSONArray?): MutableList<IptvListEntry>` | 8939–8949 | 8818(initIptvMode) | Pure. Tests/anchors: none. |
| `fun parseStringList(array: JSONArray?): MutableList<String>` | 8951–8955 | 8819(initIptvMode) | Pure. Generic name — no other `parseStringList` in package. Tests/anchors: none. |
| `fun parseIptvChannels(array: JSONArray): MutableList<IptvChannelEntry> + overload fun parseIptvChannels(list: List<*>)…` | 8957–9002; 9004–9045 | 8830(initIptvMode), 10802(requestIptvBrowse), 11755(requestIptvChannelJump), 11897(requestIptvZapPage) | TWO overloads (8957, 9004) — both pure (only call iptvChannelEntry); MUST move together (a member overload left behind would win over the top-level one at every in-class call site). Tests/anchors: none. |
| `fun iptvChannelEntry(index: Int, …20 params…): IptvChannelEntry` | 9047–9096 | 8960(parseIptvChannels), 9018(parseIptvChannels) | Pure factory; only called by the two parseIptvChannels overloads — move as a unit. Tests/anchors: none. |

**Group lines:** 173

### C. Recording URL rules → `IptvRecordingUrlRules.kt`

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun isSegmentedStreamUrl(url: String): Boolean` | 9258–9272 (fun@9264) | 9276(isCurrentIptvSegmented), 9308(engineRecordableUrl) | Pure. Callers are almost-pure (isCurrentIptvSegmented / engineRecordableUrl read `iptvHlsForcedUrls`/`currentIptvStreamUrl`) and stay. Tests/anchors: none. |
| `fun xtreamTsTwin(url: String): String?` | 9279–9295 (fun@9286) | 465(performIptvLiveRetune), 9309(engineRecordableUrl) | Pure (regex). Tests/anchors: none. |
| `fun sanitizeRecordingName(raw: String): String` | 9667–9672 | 9406(toggleIptvRecording), 9508(toggleEngineRecording) | Pure. Tests/anchors: none. |
| `fun recordingTimestamp(): String` | 9674–9676 | 9406(toggleIptvRecording), 9508(toggleEngineRecording) | Pure wrt activity (reads wall clock via Date()). Expression body. Tests/anchors: none. |

**Group lines:** 41

### D. IPTV entry / EPG rules → `IptvEntryRules.kt`

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun isIptvSeriesSentinel(entry: IptvChannelEntry): Boolean` | 10185–10186 | 9829(setupIptvOverlay), 9848(setupIptvOverlay) | Pure, expression body. Tests/anchors: none. |
| `fun isStremioIptvUrl(url: String): Boolean` | 14132–14132 | 14356(beginIptvPlayback) | Pure, 1 line. Tests/anchors: none. |
| `fun iptvQualityFromLabel(label: String): String` | 14417–14426 | 14409(populateIptvStremioSources) | Pure. Tests/anchors: none. |
| `fun currentIptvStartOverProgramme(entry: IptvChannelEntry): IptvEpgProgram?` | 11162–11181 | 11188(updateIptvStartOverButton), 11244(toggleIptvStartOver) | Pure wrt activity (System.currentTimeMillis()). Name says `current` but takes the entry as a param; scanner flagged `title` only as a named argument. Tests/anchors: none. |
| `fun formatIptvRemaining(ms: Long): String` | 13954–13961 (fun@13955) | 13867(paintStyledZapBannerEpg), 13928(paintIptvZapBannerEpg) | Pure. Tests/anchors: none. |
| `fun adoptIptvEpg(from: IptvChannelEntry, to: IptvChannelEntry)` | 13980–14002 (fun@13990) | 13974(refreshIptvZapBannerPosition) | Pure wrt activity; mutates its `to` parameter (fields are vars on internal IptvChannelEntry). Tests/anchors: none. |

**Group lines:** 64

### E. Stremio TV guide data → `StremioTvGuideData.kt`

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun buildNowPlayingText(channel: StremioTvGuideChannel): String` | 19423–19431 | 19385(updateStremioTvGuideHeader) | Pure. Local `val title` shadows Activity.getTitle() today; at top level it is just a local — same semantics. Tests/anchors: none. |
| `fun updateStremioTvGuideChannelData(channel: StremioTvGuideChannel, data: Map<*, *>)` | 19548–19571 | 19651(playStremioTvPlaybackMap) | Pure wrt activity; mutates parameter. Tests/anchors: none. |

**Group lines:** 33

### F. Track / subtitle labels → `TvTrackLabels.kt`

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun buildAudioTrackLabel(format: Format): String` | 15557–15570 | 14628(umAudioTracks), 15486(showAudioTrackDialog) | Pure (Locale.getDefault()). Format fields — verify lint; add @OptIn if flagged. Tests/anchors: none. |
| `fun buildSubtitleTrackLabel(format: Format): String` | 15572–15581 | 15528(showSubtitleTrackDialog), 15598(rebuildSubtitleTrackList) | Pure. Tests/anchors: none. |
| `fun languageOfOverride(override: TrackSelectionOverride?): String?` | 14119–14128 (fun@14120) | 14774(umAudioModel), 15512(showAudioTrackDialog) | Pure. `TrackGroup.getFormat` is media3 — add @OptIn(UnstableApi::class). Tests/anchors: none. |
| `fun isSearchSubtitleOption(label: String): Boolean` | 15719–15721 | 15644(class-body), 15738(applySelectedSubtitleTrack) | Uses companion `private const SEARCH_SUBTITLE_LABEL` (only use is here, line 15720) → move const too as top-level `private const val` in the new file and delete from companion. Tests/anchors: none. |
| `fun isLoadingSubtitleOption(label: String): Boolean` | 15723–15725 | 15643(class-body) | Pure; hard-codes "⏳" (companion SUBTITLE_LOADING_LABEL not referenced). Tests/anchors: none. |
| `fun isExternalSubtitleOption(label: String): Boolean` | 15727–15729 | 15314(umSelectStremioSubtitleByUrl), 15743(applySelectedSubtitleTrack), 15747(applySelectedSubtitleTrack) | Uses companion `private const EXTERNAL_SUBTITLE_PREFIX`, ALSO used by activity at 15614 → must become top-level `internal const val` (delete companion copy; 15614 then resolves to the top-level const). Declared substitution, not verbatim. Tests/anchors: none. |
| `fun isSideRenderableSubtitle(url: String): Boolean` | 15788–15797 (fun@15794) | 5087(seedInjectedSubtitles), 5138(launchAddonSubtitleFetch) | Pure. (Torbox Java has a same-named private method — irrelevant to Kotlin resolution.) Tests/anchors: none. |

**Group lines:** 53

### G. Subtitle search query / identity → `SubtitleSearchQuery.kt`

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun parseSubtitleCatalogResults(result: Any?): List<SubtitleCatalogResult>` | 6334–6356 | 6311(requestSubtitleCatalogSearchFromFlutter) | Pure (raw-map validation boundary). Tests/anchors: none. |
| `fun resolveSeasonEpisodeForSubtitle(item: PlaybackItem): SeasonEpisode?` | 6565–6573 | 6200(showSearchSubtitleDialog), 15281(umPickSearchResult) | Pure transitively (calls parseSeasonEpisodeFromTitle) — move together. Tests/anchors: none. |
| `fun parseSeasonEpisodeFromTitle(title: String): SeasonEpisode?` | 6575–6592 | 6572(resolveSeasonEpisodeForSubtitle) | Pure; param `title` shadows Activity.title today — no change at top level. Tests/anchors: none. |
| `fun buildSubtitleSearchInitialQuery(item: PlaybackItem): String` | 6594–6611 | 6045(showSearchSubtitleDialog), 6634(currentSubtitleIdentityLabel), 14727(class-body) | Pure. Tests/anchors: none. |
| `fun buildManualSubtitleDisplayLabel(result: SubtitleCatalogResult, type: String, season: Int?, episode: Int?): String` | 6613–6625 | 6528(applyManualSubtitleIdentity) | Pure (SubtitleCatalogResult.titleLine() is a member of the internal data class in TvPlaybackPayload.kt). Tests/anchors: none. |

**Group lines:** 81

### H. Formatting / seek math → `TvPlayerFormatting.kt`

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun formatTime(ms: Long): String` | 16947–16959 (fun@16948) | 7680(updateSeekbarProgress), 7682(updateSeekbarProgress), 7684(updateSeekbarProgress), 7688(updateSeekbarProgress), 7688(updateSeekbarProgress), 7920(updateCinemaProgressUI), 7923(updateCinemaProgressUI), 7925(updateCinemaProgressUI) … (+4) | Pure (String.format default locale, unchanged). COLLISION CHECK: SubtitleLinePickerController.kt:564 has `private fun formatTime(ms: Long)` MEMBER — member wins inside that class, so no behaviour change and no ambiguity; dart test/calendar_display_preferences_test.dart match is an unrelated Dart symbol. Tests/anchors: none. |
| `fun spellNumber(n: Int?): String` | 5880–5897 (fun@5882) | 5681(updateOttIdentity), 5681(updateOttIdentity) | Pure. Tests/anchors: none. |
| `fun getAcceleratedSeekStep(repeatCount: Int): Long` | 8036–8043 | 7157(dispatchKeyEvent), 7162(dispatchKeyEvent), 7750(setupCinemaProgressBar), 7757(setupCinemaProgressBar) | Pure (local constants, not companion SEEK_STEP_MS). Tests/anchors: none. |

**Group lines:** 39

### I. Unified-menu row factory → `UnifiedMenuRows.kt` (or top of existing UnifiedMenuSections.kt)

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun mrow(title: String, value: String? = null, …, onAdjust: ((Int) -> Unit)? = null): UnifiedMenuController.Row` | 14662–14666 | 14675(umSectionRows), 14676(umSectionRows), 14677(umSectionRows), 14678(umSectionRows), 14751(umAudioModel), 14752(umAudioModel), 14757(umAudioModel), 14760(umAudioModel) … (+39) | Pure; default params are literals only. Return type is the public nested `UnifiedMenuController.Row` (fine for internal fun). 47 call sites, all in um* builders. Param `title` shadows Activity.title already. Tests/anchors: none. |

**Group lines:** 5

### J. Startup / source diagnostics & protected origins → `TvStartupDiagnostics.kt` (+ origins could go to ProtectedStreamHttp.kt)

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun originKey(uri: Uri): String?` | 2690–2701 | 2684(buildProtectedMediaOrigins), 2868(setupPlayer), 18567(switchToStremioSource) | Pure. Tests/anchors: none. |
| `fun buildProtectedMediaOrigins(...)` | 2678–2688 | 4568(playItem), 4620(playItem), 4773(startPlayback) | Pure transitively (only calls originKey) — move with originKey. Tests/anchors: none. |
| `fun diagnosticProvider(value: String?): String` | 17560–17567 | 2121(onCreate) | Pure. Tests/anchors: none. |
| `fun startupLog(message: String, warning: Boolean = false)` | 17569–17578 | 1830(class-body), 1850(class-body), 2138(onCreate), 2140(onCreate), 4666(resolveAndPlay), 4682(resolveAndPlay), 4694(resolveAndPlay), 4709(resolveAndPlay) … (+28) | Side effect = DiagnosticFileLog (object) + android.util.Log; no activity state. Uses companion `private const STARTUP_FAILOVER_LOG_TAG` (only used here, 17576/17577) → move const as file-private. 36 callers. Tests/anchors: none. |
| `fun isPikPakPlaybackItem(item: PlaybackItem?): Boolean` | 17483–17485 | 17488(currentPlaybackItemIsPikPak) | Uses companion `private const PROVIDER_PIKPAK`, ALSO used at 4784 and 18645 → make top-level `internal const val PROVIDER_PIKPAK` and delete companion copy (Torbox Java has its own; no clash). Declared substitution. Tests/anchors: none. |
| `fun androidDecoderStatus(decoderName: String): String` | 318–339 | 301(class-body) | Pure (MediaCodecList query, SDK_INT). Only caller is inside the anonymous AnalyticsListener (301). Tests/anchors: none. |

**Group lines:** 66

### K. Playlist navigation targeting → `PlaylistNavigationMaps.kt`

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun rebuildNavigationMaps(model: PlaybackPayload, contentType: String)` | 18494–18535 | 18211(switchToSourcePlaylist), 18432(switchToSourcePlaylist) | Pure wrt activity; mutates the passed `model` (contentType/next/prev maps/collectionGroups/perItemImdbIds — all var/mutable on internal PlaybackPayload). Callers pass `payload` explicitly. Tests/anchors: none. |

**Group lines:** 42

### L. Flutter channel requests — activity-pure but belong to the phase-2 `TvPlayerFlutterBridge` seam, NOT the pure-helper files

| Function (becomes `internal fun`) | Lines (incl. KDoc) | Callers (line(enclosing fun)) | Verification / collisions / reflection / anchors |
|---|---|---|---|
| `fun requestStreamFromFlutter(item: PlaybackItem, index: Int, callback: (String?, String?) -> Unit)` | 5927–5964 | 4673(resolveAndPlay), 4675(resolveAndPlay), 4687(resolveAndPlay), 4704(resolveAndPlay), 4715(resolveAndPlay), 4721(resolveAndPlay), 5541(playShowShuffle), 5542(playShowShuffle) | Pure wrt activity (MainActivity.getAndroidTvPlayerChannel() static). Callback thread = MethodChannel (main). Tests/anchors: none. |
| `fun requestMovieMetadataFromFlutter(item: PlaybackItem, index: Int, callback: (String?) -> Unit)` | 5984–6023 (fun@5988) | 5043(fetchStremioSubtitles), 5046(fetchStremioSubtitles), 5057(fetchStremioSubtitles) | Same. Tests/anchors: none. |
| `fun requestIptvEpg(entry: IptvChannelEntry, includeSchedule: Boolean, includeCatchupMetadata: Boolean = entry.isCurrent, callback: (Map<*, *>?) -> Unit)` | 11404–11471 (fun@11411) | 10913(ensureIptvChannelEpg), 11029(showIptvSchedulePane), 11033(showIptvSchedulePane) | Default value references only the param. Creates its OWN Handler(Looper.getMainLooper()) + 45s watchdog — not an activity handler, so the watchdog is not cancelled on destroy today (unchanged by a move). Tests/anchors: none. |
| `fun reportIptvStreamResult(channelUrl: String, url: String?, success: Boolean)` | 14599–14611 (fun@14600) | 14483(tryNextIptvStremioCandidate), 14544(reportIptvStremioWinnerIfNeeded) | Fire-and-forget. Tests/anchors: none. |
| `fun requestQuickPlayNextEpisode(imdbId: String, season: Int, episode: Int)` | 16935–16945 | 1790(class-body), 5269(playNext) | Fire-and-forget. Tests/anchors: none. |

**Group lines:** 170
### IptvLiveLoadErrorPolicy (lines 700–749 incl. KDoc; class 709–749): is it a near-verbatim move?

Yes. It is a verbatim move plus three declared substitutions. Nothing else in the body touches the activity. The body only uses `C`, `HttpDataSource`, `LoadErrorHandlingPolicy` and `super`, and `liveNow()` is its only capture.

```kotlin
// IptvLoadErrorPolicy.kt (with classifyIptvError)
@OptIn(UnstableApi::class)                       // DefaultLoadErrorHandlingPolicy is @UnstableApi
internal class IptvLiveLoadErrorPolicy(
    private val liveNow: () -> Boolean,           // replaces `private fun liveNow()` (710–711)
) : DefaultLoadErrorHandlingPolicy() {
    // 713–748 verbatim: `liveNow()` now invokes the function-typed property (same syntax)
}
// call site 2960:
.setLoadErrorHandlingPolicy(IptvLiveLoadErrorPolicy { iptvChannels.getOrNull(currentIptvIndex)?.isLive == true })
```

Declared substitutions:
1. `private inner class` becomes `internal class` with a constructor supplier, and the activity's `@OptIn` is replaced by its own.
2. The 2-line `liveNow()` member is deleted, and its expression moves verbatim into the call-site lambda.
3. The call site changes from `IptvLiveLoadErrorPolicy()` to `IptvLiveLoadErrorPolicy { … }`.

Notes on the move:
- **Threading is unchanged.** The lambda still reads non-volatile `iptvChannels` and `currentIptvIndex` on the loader thread, which is the known follow-up recorded in plan line 397. The move does not fix it.
- **JVM name changes** from `AndroidTvTorrentPlayerActivity$IptvLiveLoadErrorPolicy` to `IptvLiveLoadErrorPolicy`. No test reflects it (grep of android/app/src/test and test/), and there is no name clash in the package.
- **One instance per media-source-factory build**, as today. The lambda captures the activity just as the inner class captured `this@Activity`, so lifetime is unchanged.
- **Unit testing:** it becomes testable with a fake `liveNow` and `LoadErrorInfo`. The deps survey (row 1970 and §471) already lists the retry-delay contract to characterize.

### Pairs that move together only with a nested type (still activity-free)

| Item | Lines | Notes |
|---|---|---|
| `requestIptvStreamUrls(channelUrl, channelName, callback: (List<IptvStremioCandidate>, String?) -> Unit)` | 14548–14597 (fun@14552) | Its only "member" reference is the **private nested** `data class IptvStremioCandidate` (14133–14135). An `internal` top-level fun cannot expose a private nested type, so the type must move to top-level `internal data class IptvStremioCandidate` in the same batch. The activity's `private var iptvStremioCandidates: List<IptvStremioCandidate>` (1080) and `tryNextIptvStremioCandidate` then resolve to the top-level type unchanged. Not reflected in tests. This is a Flutter-bridge member, so it belongs with group L. Callers: grep `requestIptvStreamUrls(` (beginIptvPlayback/populate path). |

### Nested value types / consts

| Type | Lines | Movable? |
|---|---|---|
| `data class TvSourceAddon(id, name, sourceKey)` (public nested) | 1171 | Yes, self-contained. Uses: 1172 property, 18832 construction. No qualified `AndroidTvTorrentPlayerActivity.TvSourceAddon` uses anywhere, and not in tests. The JVM name changes. Low value alone. |
| `private data class SkipSegmentRequest` | 1243–1250 | Yes, self-contained. Uses 8135/8154/8199, all in stateful skip-segment code. Low value alone. |
| `private enum class SleepTimerMode` | 1268 | Yes, self-contained. Uses 414, 1269, 1680, 1715, 8337–8370, 15429/15442. The Dart `SleepTimerMode` (lib/screens/video_player/widgets/sleep_timer_sheet.dart) is unrelated, with no clash. |
| `private data class DockSkinSpec` | 12576–12592 incl. KDoc | Yes, the type itself is pure. Its `by lazy` instance (12596+) reads `controlsSkin`/`R.layout` and stays. |
| `private data class IptvStremioCandidate` | 14133–14135 | Yes, together with requestIptvStreamUrls (above). |
| `private class ShufflePlaybackAttempt` | 5394–5402 | **NO.** `ShufflePlaybackFlowTest.kt:27` finds it via `activity.javaClass.declaredClasses.first { it.simpleName == "ShufflePlaybackAttempt" }`, so moving it needs the test retargeted through TvPlayerOriginalAccess first. |
| Companion consts affected by group moves | 19914+ | `SEARCH_SUBTITLE_LABEL` and `STARTUP_FAILOVER_LOG_TAG` are single-use, so they move as file-private. `EXTERNAL_SUBTITLE_PREFIX` (also used at 15614) and `PROVIDER_PIKPAK` (also used at 4784 and 18645) must become top-level `internal const val`, and their companion copies must be deleted. If a companion copy were left in place, it would shadow the top-level const inside the class. That is harmless but duplicates the value. `PAYLOAD_KEY` (public) is untouched. |

### Excluded: almost-pure (1–2 activity members) — NOT phase-2 verbatim moves

The middle column lists the remaining non-pure references, after removing named arguments and references to pure-set functions. `this` means it needs a Context (Glide.with, DateFormat, DefaultDataSource.Factory, prefs, TextView(this)).

Notable ones:
- **Context-only.** These could become top-level with a `context: Context` param, but that is a signature change:
  - formatEpgTime (11003)
  - buildMergedSourceOrNull (4887) and buildMergedSource (4919)
  - loadGuideArt (3485)
  - zapText (12676)
  - isAutoSyncPrefEnabled (15249)
  - dp/dpToPx (resources)
- **One state read.** These could become pure policies with that value as a param:
  - guideAdjacent (16756, `hasAdjacentEpisodeResolver`)
  - computeMovieGroups (8555, `payload`)
  - startupWatchdogShouldExtend (17532, `player` + `currentPlaybackItemIsPikPak`; also uses companion STARTUP_*_MAX_WAIT_MS)
  - startupSourceFields (17546, `stremioSources`)
  - engineRecordableUrl (9302) and isCurrentIptvSegmented (9274) (`iptvHlsForcedUrls`/`currentIptvStreamUrl` around the pure recording rules)
  - recordingResourceFor (9335)
  - currentSubtitleIdentityLabel (6627)
  - requestSubtitleCatalogSearchFromFlutter (6294, only `runOnUiThread`; bridge seam)
  - umAudioTracks/umAudioSelectedIndex (`player`)
  - umSectionRows (`stremioSubtitles`)
  - umAddLoadMoreRow
  - iptvMediaCodecSelector (2715)
  - readStagedExtra (2229, `cacheDir`)
  - requestMetadataFromFlutter (2454, `payload`)
  - guideTitleFor (5590, `payload`)
  - currentPlaybackItemIsPikPak (17487)

Full list:

| Function | Lines | Remaining activity refs |
|---|---|---|
| `clearParkedIptvTwinRestore` | 641–644 | `iptvTwinTrialRestoreOriginal`, `iptvTwinTrialRestoreTwin` |
| `hideIptvReconnectPill` | 777–779 | `iptvReconnectPill` |
| `dpToPx` | 781–782 | `resources` |
| `releaseResumeHold` | 1408–1410 | `resumeHoldTargetMs` |
| `readStagedExtra` | 2229–2248 | `cacheDir` |
| `requestMetadataFromFlutter` | 2454–2484 | `payload` |
| `iptvMediaCodecSelector` | 2715–2734 | `iptvDecoderMode`, `isIptvMode` |
| `setupSeekbar` | 3135–3144 | `hideSeekbar`, `seekbarOverlay` |
| `guideSkinBind` | 3379–3437 | `controlsSkin` |
| `loadGuideArt` | 3485–3494 | `this` |
| `selectSeasonTab` | 3747–3761 | `playlistView`, `seasonTabs` |
| `findNextFocusablePosition` | 3860–3889 | `moviePlaylistAdapter`, `seriesPlaylistAdapter` |
| `selectMovieTab` | 4120–4133 | `movieTabs`, `playlistView` |
| `updateOttCaption` | 4230–4239 | `ottCaptionLabel`, `ottCaptionOwner` |
| `clearOttCaption` | 4241–4246 | `ottCaptionLabel`, `ottCaptionOwner` |
| `refreshOttCaptionFor` | 4250–4253 | `ottSkinInstalled`, `updateOttCaption` |
| `buildMergedSourceOrNull` | 4888–4914 | `this` |
| `buildMergedSource` | 4919–4933 | `this` |
| `setAddonSubtitleSlot` | 5162–5173 | `addonSubtitleResults` |
| `shuffleAttemptCurrent` | 5407–5408 | `ShufflePlaybackAttempt`, `shuffleAttemptOwned` |
| `restoreShufflePreparation` | 5415–5419 | `ShufflePlaybackAttempt`, `mediaPreparationGeneration` |
| `clearQueuedShuffle` | 5447–5452 | `queuedShuffleGeneration`, `queuedShuffleNavigation` |
| `guideTitleFor` | 5590–5595 | `payload` |
| `dockTagsFor` | 5857–5878 | `dockTagsCache`, `dockTagsCacheKey` |
| `reportValidatedSourceCommit` | 5966–5982 | `sourcePersistenceSessionId`, `stremioSources` |
| `requestSubtitleCatalogSearchFromFlutter` | 6294–6332 | `runOnUiThread` |
| `createSubtitleCatalogResultAdapter` | 6358–6404 | `dp`, `this` |
| `currentSubtitleIdentityLabel` | 6627–6642 | `getCurrentSubtitleSearchItem`, `manualSubtitleDisplayLabel` |
| `dp` | 6644–6646 | `resources` |
| `isFocusInControlsOverlay` | 7381–7390 | `controlsOverlay`, `currentFocus` |
| `isFocusInIptvChannelList` | 7392–7401 | `currentFocus`, `iptvGuideList` |
| `cancelScheduledHideControlsMenu` | 7622–7624 | `controlsHandler`, `hideControlsRunnable` |
| `startSeekbarProgressUpdates` | 7653–7656 | `seekbarHandler`, `seekbarProgressRunnable` |
| `stopSeekbarProgressUpdates` | 7658–7660 | `seekbarHandler`, `seekbarProgressRunnable` |
| `updateCinemaSeekSpeed` | 7913–7916 | `currentSeekSpeed` |
| `updateSeekSpeed` | 8063–8072 | `currentSeekSpeed`, `seekbarSpeedIndicator` |
| `releaseScreenForSleep` | 8395–8398 | `playerView`, `window` |
| `holdScreenForPlayback` | 8401–8404 | `playerView`, `window` |
| `computeMovieGroups` | 8555–8641 | `payload` |
| `fadeInNextOverlay` | 8656–8661 | `nextOverlay` |
| `hideNextOverlay` | 8663–8670 | `nextOverlay` |
| `isCurrentIptvSegmented` | 9274–9277 | `currentIptvStreamUrl`, `iptvHlsForcedUrls` |
| `engineRecordableUrl` | 9302–9310 | `iptvHlsForcedUrls` |
| `isSchedulableStreamUrl` | 9319–9325 | `engineRecordableUrl` |
| `engineTaskIdForCurrentChannel` | 9329–9333 | `currentIptvStreamUrl`, `engineRecordableUrl` |
| `recordingResourceFor` | 9335–9338 | `iptvSourceId`, `iptvSources` |
| `replaceControlDockOrder` | 9765–9776 | `originalControlDockOrder` |
| `commitIptvAllCategorySearch` | 10294–10297 | `clearIptvAllCategorySearchState`, `iptvAllCategorySearchActive` |
| `focusCurrentIptvGuideRow` | 10308–10317 | `iptvChannelAdapter`, `iptvGuideList` |
| `focusedIptvGuideEntry` | 10994–11001 | `iptvChannelAdapter`, `iptvGuideList` |
| `formatEpgTime` | 11003–11004 | `this` |
| `isFocusInIptvEpgPanel` | 11393–11402 | `currentFocus`, `iptvEpgPanel` |
| `boundedHiddenIptvZapWindow` | 12024–12032 | `iptvGuideVisible`, `iptvZapMaxHiddenWindow` |
| `queuePendingIptvZapInput` | 12069–12073 | `iptvZapPendingInputs` |
| `adjacentIptvCategory` | 12109–12119 | `iptvZapCategories`, `iptvZapCategory` |
| `guideTypeface` | 12656–12667 | `assets`, `guideTypefaces` |
| `zapText` | 12676–12692 | `this` |
| `styledZapText` | 12951–12973 | `guideTypeface`, `this` |
| `setIptvPreferredAudioLang` | 14094–14104 | `trackSelector` |
| `cancelIptvStremioStallWatchdog` | 14532–14535 | `iptvStremioStallRunnable`, `progressHandler` |
| `requestIptvStreamUrls` | 14552–14597 | `IptvStremioCandidate` |
| `umAudioTracks` | 14620–14635 | `player` |
| `umAudioSelectedIndex` | 14638–14650 | `player` |
| `umSectionRows` | 14668–14680 | `stremioSubtitles` |
| `umAppearanceRows` | 14874–14877 | `applyAndPersistSubtitleSettings`, `this` |
| `isAutoSyncPrefEnabled` | 15249–15254 | `this` |
| `umAddLoadMoreRow` | 15344–15356 | `moreSourcesLoadingMode`, `requestMoreTorrentSources` |
| `hideSubtitleSettingsPanel` | 15668–15670 | `subtitlePanel`, `subtitleSettingsVisible` |
| `refreshSubtitlePanelForLoading` | 15714–15717 | `rebuildSubtitleTrackList`, `subtitlePanel` |
| `revealAutoSyncPill` | 16166–16175 | `autoSyncPill`, `dp` |
| `applyAndPersistSubtitleSettings` | 16249–16255 | `applySubtitleSettings`, `this` |
| `releaseLoudnessEnhancer` | 16332–16339 | `loudnessEnhancer` |
| `restartProgressUpdates` | 16436–16439 | `progressHandler`, `progressRunnable` |
| `acknowledgeRecoveryCheckpoint` | 16582–16584 | `filesDir`, `sourcePersistenceSessionId` |
| `sendPlaybackMaintenanceState` | 16712–16720 | `player`, `sourcePersistenceSessionId` |
| `sendPlaybackActivityState` | 16722–16734 | `sendPlaybackMaintenanceState`, `sourcePersistenceSessionId` |
| `guideAdjacent` | 16756–16771 | `hasAdjacentEpisodeResolver` |
| `startupCandidateElapsedMs` | 17479–17481 | `startupCandidateStartedElapsedMs` |
| `currentPlaybackItemIsPikPak` | 17487–17488 | `currentIndex`, `payload` |
| `cancelPikPakGateReprepare` | 17490–17493 | `pikPakGateReprepare`, `progressHandler` |
| `startupWatchdogShouldExtend` | 17532–17544 | `currentPlaybackItemIsPikPak`, `player` |
| `startupSourceFields` | 17546–17558 | `stremioSources` |
| `mediaServerPlaybackLog` | 17580–17587 | `currentStremioSourceIndex`, `stremioSources` |
| `updateStremioQualityBadge` | 17617–17620 | `stremioSourceBadgeText`, `stremioSources` |
| `failAddonFetch` | 18148–18151 | `addonFetchState`, `sourceBrowser` |
| `hideStremioSourceBadge` | 18673–18685 | `stremioSourceBadge` |
| `hideStremioSourceBadgeImmediately` | 18690–18695 | `stremioSourceBadge` |
| `isFocusInStremioTvGuideList` | 19433–19442 | `currentFocus`, `stremioTvGuideList` |
All other members (≈350) touch 3+ activity members, views, handlers or the player, and are out of scope.

### Totals

| Group | Lines (incl. KDoc) |
|---|---|
| A classifyIptvError | 17 |
| B IPTV payload parsing | 173 |
| C Recording URL rules | 41 |
| D IPTV entry/EPG rules | 64 |
| E Stremio TV guide data | 33 |
| F Track/subtitle labels | 53 (+2 consts) |
| G Subtitle search query | 81 |
| H Formatting/seek | 39 |
| I mrow | 5 |
| J Startup diagnostics/origins | 66 (+2 consts) |
| K Playlist navigation maps | 42 |
| **Pure helpers A–K** | **614 lines, 41 functions (42 decls incl. 2 parseIptvChannels overloads)** |
| L Flutter bridge requests (activity-pure; bridge seam) | 170 lines, 5 functions |
| **All activity-pure members** | **784 lines, 46 names / 47 decls** (736 lines without KDoc) |
| IptvLiveLoadErrorPolicy (declared substitution) | 50 |
| requestIptvStreamUrls + IptvStremioCandidate (pair) | 50 + 3 |
| Self-contained nested value types (TvSourceAddon, SkipSegmentRequest, SleepTimerMode, DockSkinSpec) | ≈1 + 8 + 1 + 17 |
| **Upper bound removable in phase 2 without touching stateful code** | **≈914 lines** (≈4.6% of 19,961). That is well short of the plan's 2,000-line phase-2 estimate, so the remainder must come from the Flutter bridge seam (which wraps state-touching callers) and the "almost-pure" policies after a parameterization step. |

## Phase 2 step 0 preflight — stopped on the opt-in-set check

Historical stop at `108afb530`; resolved by approved plan correction
`861aa13ed` and manifest correction `5bb66a997`. Completed step-0 evidence
follows below.

At original production revision `dcbd9aafe`, the actual cached Media3
1.8.0 AAR class files derive this required declaration opt-in set:

| Declaration | Annotated API used |
|---|---|
| `IptvLiveLoadErrorPolicy` | `DefaultLoadErrorHandlingPolicy`, `LoadErrorHandlingPolicy`, and `InvalidResponseCodeException.headerFields` |
| `languageOfOverride` | `TrackGroup.getFormat` |
| `buildAudioTrackLabel` | `Format.bitrate` |

**This differs from the approved four-declaration set.**
`classifyIptvError` uses the stable `PlaybackException` type, `errorCode`,
three decoder error constants, and the stable
`HttpDataSource.InvalidResponseCodeException` type and `responseCode`
field. None of those symbols has `@UnstableApi` in these artifacts.
The constructor and `headerFields` of the HTTP exception do have that
annotation, but the classifier uses neither. The inventory's earlier
claim that the exception type itself needs opt-in is superseded by this
artifact audit. `buildSubtitleTrackLabel` uses stable Format fields and
requires no opt-in. The selected declaration bodies were inspected for
Media3 references; the other moved helpers have none.

Evidence under the common Git evidence root: `p2/media3_annotations.py`,
`p2/media3-opt-in-audit.json` (artifact versions, SHA-256 identities, symbol
annotations, expected/derived sets), `p2/media3-opt-in-audit.log` (the
required stop assertion), `p2/media3-annotation-inventory.json`, and the
independent `javap -v` captures `p2/PlaybackException-javap.txt` and
`p2/HttpDataSource$InvalidResponseCodeException-javap.txt`. The phase-2
manifest still encodes the approved four opt-ins; no silent design change
was made. Resolve this mismatch before proceeding with step 0.

The clean original JVM run is archived as
`junit/baseline-dcbd9aafe/identities.json`: **323 identities, 322 pass,
one existing `TvSourceBrowserFocusTest` failure, no skips**, JBR 21.0.10,
zero dirty files and equal before/after tree fingerprints. Gradle exits 1
for that existing failure; the identity archive is complete, not aborted.
The command was `python3 dev/tool/android_junit_evidence.py --worktree
<detached-original> run baseline-dcbd9aafe`.

Original `./gradlew :app:lintDebug --console=plain` also exits 1: **253
errors, 1,100 warnings**, including **175 `UnsafeOptInUsageError` issues**.
The complete original issue set and XML/text/HTML reports are archived in
`p2/lint-baseline-dcbd9aafe/`; raw output is `p2/lint-original.log`. These
are original findings, not accepted new regressions.

No characterization tests or mutation proofs were added after the
explicit stop condition. There is no `p2-step0` baseline or additions-only
comparison yet. Typed selectors, fake messenger, policy/default-dispatch
coverage, constant-reference grep and the mutation table remain pending.
The detached original worktree was removed after archiving these runs.
Production source, `pubspec.lock`, ProGuard and phase-1 manifest are
unchanged.

## Phase 2 step 0 — characterization of `dcbd9aafe`

The approved correction in `861aa13ed` resolves the preflight stop above.
Manifest correction `5bb66a997` and the complete fixture pin exactly three
opt-ins: `languageOfOverride`, `buildAudioTrackLabel`, and
`IptvLiveLoadErrorPolicy`. A fresh annotation audit of the actual cached
Media3 1.8.0 AARs matches that set; `classifyIptvError` has none.

Added **55 named characterization tests in ten behavior-focused classes**.
All **48 moved function declarations** (both channel overloads included)
are called directly via exact parameter-type selectors on an un-created
Robolectric activity. The nested policy is constructed by its original
binary name and exact outer-activity constructor type; stream candidates'
original binary name and typed getters are also pinned. Existing phase-1
reflection callers and assertions are unchanged. No player is created.

| Coverage class | Tests | Contracts pinned |
|---|---:|---|
| `TvIptvParsingCharacterizationTest` | 6 | Null/empty/malformed arrays, source/list defaults and filtering, exact overload selection, raw indexes, complete channel fields, header canonicalization and JSON/map differences |
| `TvIptvRulesCharacterizationTest` | 10 | Segmented suffixes, strict/token-safe twins, filename limit, local-zone US-digit timestamp, sentinel/prefix/quality rules, archive eligibility/window/retention, remaining-time boundaries and EPG ownership |
| `TvFormattingCharacterizationTest` | 4 | Second/hour boundaries, number spelling, seek cap, row values/callbacks and actual omitted-argument defaults |
| `TvSubtitleHelpersCharacterizationTest` | 12 | First override index and failure fallback, track labels/locales/defaults, three subtitle sentinels, supported URL suffixes, catalog validation/order, title patterns/metadata priority, query cleaning and manual labels |
| `TvGuideDataCharacterizationTest` | 2 | Loading/title/year/rating formatting, section-presence updates, empty/malformed values and loading reset |
| `TvStartupHelpersCharacterizationTest` | 7 | Origin normalization/deduplication, provider strings, PikPak detection, pre-Q/Q codec flags and lookup failure, structured diagnostic records and Android log levels/tag |
| `TvNavigationCharacterizationTest` | 1 | Stable chronological series order, missing metadata, collection/raw order, empty/single playlists and stale map/group/IMDB clearing |
| `TvIptvLoadPolicyCharacterizationTest` | 4 | Error classification; one policy instance with live → non-live → invalid index → replaced-list state; both retry methods per invocation; 4/5 and 15/16 boundaries, Retry-After fallback/clamps, status/exception handling and superclass delegation |
| `TvFlutterRequestsCharacterizationTest` | 5 | Exact request maps, success/error/notImplemented, encoded-null versus raw-null fake semantics, malformed results, per-function null-channel behavior, reporting swallow versus quick-play propagation |
| `TvEpgRequestCharacterizationTest` | 4 | Async answers/failures, real Kotlin default dispatcher for current true/false, exactly 45,000 ms, reply-before wins and late reply never redelivers |

The fake messenger flips outgoing buffers before decoding with
`StandardMethodCodec`; flipped success/error envelopes and raw-null replies
are posted through a main-looper Handler. It records fire-and-forget calls
without inventing result callbacks. The previous static MethodChannel is
saved once and restored after every test; reconnects do not overwrite it.
Locale/time-zone and diagnostic global state/crash handler are restored.
Diagnostic assertions drain the real work queue and inspect structured
records as well as the Android log. Codec-lookup and invalid-override
exception fallbacks use explicit test-only corrupt-state inputs.

All reachable Kotlin decision paths are exercised. Some defensive arms
cannot be reached through the original accepted inputs: the origin port
`else` after the HTTP/HTTPS guard; the provider `ifBlank` after nonblank
input is replaced with nonblank characters; missing/overflowing numeric
regex groups after the fixed one-to-three-digit patterns. They remain
verbatim and covered by the exhaustive checker; no fabricated production
changes were used to make these arms reachable.

Qualified-constant search across Kotlin, Java, Dart and tests has **zero
matches** for activity/companion references to the four relocated constants.
Evidence: `p2/step0/qualified-constant-references.log`; command:
`rg -n '(AndroidTvTorrentPlayerActivity|Companion)\.(SEARCH_SUBTITLE_LABEL|EXTERNAL_SUBTITLE_PREFIX|STARTUP_FAILOVER_LOG_TAG|PROVIDER_PIKPAK)' android lib test dev --glob '*.kt' --glob '*.java' --glob '*.dart'`.

### Original-code mutation proofs

**65 distinct isolated mutations, all assertion-killed; zero survivors or
compile/crash proofs. All 55 named tests have a proof.** The detached
worktree contains original `dcbd9aafe` production code plus these tests;
only one declared mutation is applied for each clean, named-test Gradle
run. The original source is restored between runs. Four proofs were
repeated after final assertion/isolation strengthening (69 proof runs in
total); their rows below refer to the final runs.

Evidence under `p2/step0/`: `mutation_catalog.py`, `mutation-catalog.json`
(exact before/after text and original spans), `run_mutations.py`,
`mutation-summary.json`, and `mutations/<ID>/` (patch, Gradle log, fresh
XML, mutation and result JSON). IDs `m05`, `m34`, `m41`, `m50` additionally
use `mutations-final-assertions/<ID>/`; every retained proof is a named
JUnit assertion failure. Long model-equality messages below show the first
changed field; XML retains the complete failure and stack trace.

| ID | Named test | Original mutation | Failing assertion |
|---|---|---|---|
| m01 | `TvIptvParsingCharacterizationTest.sourcesPreserveDefaultsFlagsFilteringAndRevisionPresence` | `it.id.isNotEmpty() && !it.isContinue → it.id.isNotEmpty() && it.isContinue` | `TvIptvParsingCharacterizationTest.kt:32`: expected [default, full, zero]; observed [skip] |
| m02 | `TvIptvParsingCharacterizationTest.listsPreserveDefaultsBuiltinAndIgnoreMalformedEntries` | `"List" → "Changed"` | `TvIptvParsingCharacterizationTest.kt:45`: expected [IptvListEntry(id=one, name=List, isBuiltin=false), IptvListEntry(id=two, name=Films, isBuiltin=true)]; observed [IptvListEntry(id=one, name=Changed, isBuiltin=false), IptvListEntry(id=two, name=Films, isBuiltin=true)] |
| m03 | `TvIptvParsingCharacterizationTest.stringListKeepsWhitespaceAndJsonCoercionButDropsEmptyStrings` | `it.isNotEmpty() → it.isNotBlank()` | `TvIptvParsingCharacterizationTest.kt:51`: expected [a,  , 4, false, null]; observed [a, 4, false, null] |
| m04 | `TvIptvParsingCharacterizationTest.jsonChannelOverloadKeepsPlaceholdersAndPinsAllOptionalFields` | `key.equals("User-Agent", ignoreCase = true) → key.equals("User-Agent", ignoreCase = false)` | `TvIptvParsingCharacterizationTest.kt:70`: expected …ionMs=5000, httpHeaders={User-Agent=Agent, Referer=r…; observed …ionMs=5000, httpHeaders={uSeR-aGeNt=Agent, Referer=r… |
| m05 | `TvIptvParsingCharacterizationTest.mapChannelOverloadFiltersByTypesAndKeepsRawIndexesAndNegativeMetadata` | `?.toInt() ?: -1 → ?.toInt() ?: 0` | `TvIptvParsingCharacterizationTest.kt:94`: expected …null, group=null, isLive=true, isCurrent=false, resum…; observed …null, group=null, isLive=false, isCurrent=false, resum… |
| m06 | `TvIptvParsingCharacterizationTest.channelFactoryInfersLiveOnlyForMissingTypeAndMinusOneDuration` | `if (duration == -1) "live" else "vod" → if (duration == 0) "live" else "vod"` | `TvIptvParsingCharacterizationTest.kt:109`: expected …ogo, group=Group, isLive=true, isCurrent=false, resum…; observed …ogo, group=Group, isLive=false, isCurrent=false, resum… |
| m07 | `TvIptvRulesCharacterizationTest.segmentedUrlsMatchOnlyKnownPathSuffixesBeforeQueryAndFragment` | `path.endsWith(".ism") → path.endsWith(".ismx")` | `TvIptvRulesCharacterizationTest.kt:16`: expected true; observed false |
| m08 | `TvIptvRulesCharacterizationTest.xtreamTwinKeepsHostCredentialsIdAndRejectsTokenOrLoosePaths` | `"$host/live/$user/$pass/$id.ts" → "$host/live/$user/$pass/$id.mp4"` | `TvIptvRulesCharacterizationTest.kt:25`: expected .../live/user/pass/123.[ts]; observed .../live/user/pass/123.[mp4] |
| m09 | `TvIptvRulesCharacterizationTest.recordingNamesStripUnsafeCharactersCollapseSpacesAndBoundLength` | `cleaned.take(60) → cleaned.take(59)` | `TvIptvRulesCharacterizationTest.kt:38`: expected ...aaaaaaaaaaaaaaaaaaaa[a]; observed ...aaaaaaaaaaaaaaaaaaaa[] |
| m10 | `TvIptvRulesCharacterizationTest.recordingTimestampUsesLocalZoneAndUsDigitsToSecondPrecision` | `"yyyyMMdd_HHmmss" → "yyyyMMdd_HHmm"` | `TvIptvRulesCharacterizationTest.kt:49`: java.lang.AssertionError |
| m11 | `TvIptvRulesCharacterizationTest.seriesSentinelRecognizesEitherExactTypeOrCaseSensitiveScheme` | `entry.contentType == "series" → entry.contentType == "Series"` | `TvIptvRulesCharacterizationTest.kt:59`: expected true; observed false |
| m12 | `TvIptvRulesCharacterizationTest.stremioUrlRequiresExactPrefixAtTheBeginning` | `url.startsWith("stremio-tv://") → url.contains("stremio-tv://")` | `TvIptvRulesCharacterizationTest.kt:66`: expected false; observed true |
| m13 | `TvIptvRulesCharacterizationTest.qualityUsesFirstCaseInsensitiveRecognizedTokenAndLiveFallback` | `-> "4K" → -> "Ultra"` | `TvIptvRulesCharacterizationTest.kt:73`: expected [4K]; observed [Ultra] |
| m14 | `TvIptvRulesCharacterizationTest.startOverRequiresLiveArchiveAndCurrentWindowWithinRetention` | `entry.tvArchive == "0" → entry.tvArchive == "1"` | `TvIptvRulesCharacterizationTest.kt:81`: expected IptvEpgProgram(title=Show, description=null, startMs=1791384910970, stopMs=1791384930970, hasArchive=true); observed null |
| m15 | `TvIptvRulesCharacterizationTest.remainingTimeFloorsMinutesAndFormatsHourRemainders` | `minutes < 60 → minutes <= 60` | `TvIptvRulesCharacterizationTest.kt:96`: expected [1 hr]; observed [60 min] |
| m16 | `TvIptvRulesCharacterizationTest.epgAdoptionCopiesRealDataWithoutOverwritingLoadedOrInFlightOwnership` | `if (!to.epgLoading) to.epgLoaded = true → if (to.epgLoading) to.epgLoaded = true` | `TvIptvRulesCharacterizationTest.kt:107`: expected …extStartMs=30, epgLoaded=true, epgLoading=false, cont…; observed …extStartMs=30, epgLoaded=false, epgLoading=false, cont… |
| m17 | `TvFormattingCharacterizationTest.playbackTimeFloorsSecondsAndCrossesHourBoundary` | `ms <= 0 → ms <= 1000` | `TvFormattingCharacterizationTest.kt:19`: expected 00:0[1]; observed 00:0[0] |
| m18 | `TvFormattingCharacterizationTest.spelledNumbersKeepNullDigitsTensHyphensAndFiftyBoundary` | `n >= 50 → n >= 49` | `TvFormattingCharacterizationTest.kt:27`: expected [Forty-Nine]; observed [49] |
| m19 | `TvFormattingCharacterizationTest.seekAccelerationKeepsBaseNegativeRepeatsAndInclusiveCap` | `120_000L → 119_000L` | `TvFormattingCharacterizationTest.kt:32`: expected 120000; observed 119000 |
| m20 | `TvFormattingCharacterizationTest.menuRowPassesValuesAndCallbacksAndUsesRealDefaultDispatch` | `Row(title, value, selected, accent, enabled, → Row(title, value, selected, accent, !enabled,` | `TvFormattingCharacterizationTest.kt:42`: expected …ue, accent=true, enabled=false, swatch=1193046, adjust…; observed …ue, accent=true, enabled=true, swatch=1193046, adjust… |
| m21 | `TvSubtitleHelpersCharacterizationTest.overrideLanguageUsesFirstIndexAndReturnsNullForMissingOrInvalidSelection` | `override.trackIndices.firstOrNull() → override.trackIndices.lastOrNull()` | `TvSubtitleHelpersCharacterizationTest.kt:24`: expected [fr]; observed [en] |
| m22 | `TvSubtitleHelpersCharacterizationTest.audioLabelsKeepLabelFallbackChannelAndBitrateBoundariesAndDefaultLocale` | `"${format.channelCount}ch" → "${format.channelCount}channels"` | `TvSubtitleHelpersCharacterizationTest.kt:35`: expected Main · 6ch[] · 128kbps; observed Main · 6ch[annels] · 128kbps |
| m23 | `TvSubtitleHelpersCharacterizationTest.subtitleLabelsKeepNamedLanguageAndUndOrEmptyFallback` | `"$label ($lang)" → "$label [$lang]"` | `TvSubtitleHelpersCharacterizationTest.kt:48`: expected English [(en)]; observed English [[en]] |
| m24 | `TvSubtitleHelpersCharacterizationTest.searchSubtitleOptionUsesExactLabelEquality` | `label == SEARCH_SUBTITLE_LABEL → label != SEARCH_SUBTITLE_LABEL` | `TvSubtitleHelpersCharacterizationTest.kt:57`: expected true; observed false |
| m25 | `TvSubtitleHelpersCharacterizationTest.loadingSubtitleOptionUsesOnlyLeadingHourglass` | `label.startsWith("⏳") → label.contains("⏳")` | `TvSubtitleHelpersCharacterizationTest.kt:62`: expected false; observed true |
| m26 | `TvSubtitleHelpersCharacterizationTest.externalSubtitleOptionUsesOnlyLeadingDownloadPrefix` | `label.startsWith(EXTERNAL_SUBTITLE_PREFIX) → label.contains(EXTERNAL_SUBTITLE_PREFIX)` | `TvSubtitleHelpersCharacterizationTest.kt:67`: expected false; observed true |
| m27 | `TvSubtitleHelpersCharacterizationTest.renderableSubtitleRejectsTtmlDfxpBeforeQueryButPreservesFragmentBehavior` | `!path.endsWith(".ttml") → path.endsWith(".ttml")` | `TvSubtitleHelpersCharacterizationTest.kt:73`: expected false; observed true |
| m28 | `TvSubtitleHelpersCharacterizationTest.subtitleCatalogValidatesTypesAndPreservesOrderTrimAndFallbacks` | `it.startsWith("tt") → it.startsWith("TT")` | `TvSubtitleHelpersCharacterizationTest.kt:85`: expected …itleCatalogResult(imdbId=tt1, type=movie, name=Film,…; observed …itleCatalogResult(imdbId=TT1, type=movie, name=TT1, … |
| m29 | `TvSubtitleHelpersCharacterizationTest.titleEpisodeParsingKeepsPatternPriorityWordBoundariesAndPositiveNumbers` | `season > 0 && episode > 0 → season >= 0 && episode > 0` | `TvSubtitleHelpersCharacterizationTest.kt:94`: S00E01 expected null, but was:<SeasonEpisode(season=0, episode=1)> |
| m30 | `TvSubtitleHelpersCharacterizationTest.subtitleEpisodePrefersBothPositiveMetadataOtherwiseParsesTitle` | `existingSeason > 0 → existingSeason >= 0` | `TvSubtitleHelpersCharacterizationTest.kt:102`: expected SeasonEpisode(season=1, episode=2); observed SeasonEpisode(season=0, episode=4) |
| m31 | `TvSubtitleHelpersCharacterizationTest.subtitleQueryRemovesPathExtensionEpisodeAndReleaseTagsOrKeepsOriginal` | `substringBefore('?') → substringBefore('#')` | `TvSubtitleHelpersCharacterizationTest.kt:112`: expected My Show[]; observed My Show[ mkv?token=x] |
| m32 | `TvSubtitleHelpersCharacterizationTest.manualSubtitleLabelAppendsEpisodeOnlyForSeriesWithBothNumbers` | `type == "series" → type == "movie"` | `TvSubtitleHelpersCharacterizationTest.kt:119`: expected Show (2024)[ S2E3]; observed Show (2024)[] |
| m33 | `TvGuideDataCharacterizationTest.nowPlayingTextKeepsLoadingYearAndPositiveRatingWithUsDecimal` | `"Loading..." → "Waiting..."` | `TvGuideDataCharacterizationTest.kt:15`: expected [Load]ing...; observed [Wait]ing... |
| m34 | `TvGuideDataCharacterizationTest.guideDataUpdatesOnlyPresentSectionsAndClearsLoadingOnEveryAnswer` | `channel.isLoadingGuideData = false → channel.isLoadingGuideData = true` | `TvGuideDataCharacterizationTest.kt:31`: expected …true, isLoadingGuideData=false, isSwitchingChannel=fal…; observed …true, isLoadingGuideData=true, isSwitchingChannel=fal… |
| m35 | `TvStartupHelpersCharacterizationTest.originsRequireHttpHostNormalizeCaseAndPreserveExplicitPorts` | `scheme == "https" -> 443 → scheme == "https" -> 444` | `TvStartupHelpersCharacterizationTest.kt:29`: expected ...ps://example.test:44[3]; observed ...ps://example.test:44[4] |
| m36 | `TvStartupHelpersCharacterizationTest.protectedOriginsSkipBlankAndNonHttpAndDeduplicateOriginsOnly` | `null ↵                 } else { → "blank" ↵                 } else {` | `TvStartupHelpersCharacterizationTest.kt:35`: expected [https://example.test:443, http://example.test:80, https://example.test:8443]; observed [blank, https://example.test:443, http://example.test:80, https://example.test:8443] |
| m37 | `TvStartupHelpersCharacterizationTest.diagnosticProviderPinsBlankSanitizationUsCaseAndThirtyTwoLimit` | `.take(32) → .take(31)` | `TvStartupHelpersCharacterizationTest.kt:42`: expected ...aaaaaaaaaaaaaaaaaaaa[a]; observed ...aaaaaaaaaaaaaaaaaaaa[] |
| m38 | `TvStartupHelpersCharacterizationTest.pikpakDetectionKeepsProviderCaseInsensitiveButUrlSubstringCaseSensitive` | `ignoreCase = true → ignoreCase = false` | `TvStartupHelpersCharacterizationTest.kt:49`: expected true; observed false |
| m39 | `TvStartupHelpersCharacterizationTest.decoderMarkersAreSoftwareAndPreQUnknownHasNoCodecLookup` | `normalized.contains(".google.") → normalized.contains(".not-google.")` | `TvStartupHelpersCharacterizationTest.kt:54`: expected [software]; observed [unknown] |
| m40 | `TvStartupHelpersCharacterizationTest.decoderQUsesCaseInsensitiveCodecFlagsAndUnknownFallback` | `if (codecInfo?.isHardwareAccelerated == true) return "hardware" → if (codecInfo?.isHardwareAccelerated == true) return "unknown"` | `TvStartupHelpersCharacterizationTest.kt:64`: expected [hardware]; observed [unknown] |
| m41 | `TvStartupHelpersCharacterizationTest.startupLogWritesStructuredEventsAndWarningOrDebugTag` | `event = "startup_gate" → event = "other_gate"` | `TvStartupHelpersCharacterizationTest.kt:92`: expected 2; observed 0 |
| m42 | `TvNavigationCharacterizationTest.navigationSortsSeriesStablyButKeepsCollectionOrderAndClearsStaleGroups` | `model.items[it].episode ?: Int.MAX_VALUE → model.items[it].episode ?: Int.MIN_VALUE` | `TvNavigationCharacterizationTest.kt:22`: expected {3=4, 4=1, 1=5, 5=0, 0=2}; observed {5=3, 3=4, 4=1, 1=0, 0=2} |
| m43 | `TvIptvLoadPolicyCharacterizationTest.errorClassificationPrioritizesFirstHttpAuthThenDecoderCodesThenTransient` | `http == 403 → http == 402` | `TvIptvLoadPolicyCharacterizationTest.kt:39`: expected AUTH; observed DECODER |
| m44 | `TvIptvLoadPolicyCharacterizationTest.policyReadsLiveStateBetweenEveryInvocation` | `same policy reads changed live state between invocations (exact text in catalog/patch)` | `TvIptvLoadPolicyCharacterizationTest.kt:55`: expected 2000; observed -9223372036854775807 |
| m45 | `TvIptvLoadPolicyCharacterizationTest.liveAuthIsFatalAndRateLimitHasFourRetryBoundWithHeaderClamps` | `loadErrorInfo.errorCount > 4 → loadErrorInfo.errorCount >= 4` | `TvIptvLoadPolicyCharacterizationTest.kt:79`: expected 5000; observed -9223372036854775807 |
| m46 | `TvIptvLoadPolicyCharacterizationTest.liveTransportEscalatesAfterFifteenAndOtherExceptionsDelegate` | `loadErrorInfo.errorCount > 15 → loadErrorInfo.errorCount >= 15` | `TvIptvLoadPolicyCharacterizationTest.kt:90`: expected 1000; observed -9223372036854775807 |
| m47 | `TvFlutterRequestsCharacterizationTest.torrentRequestsPinArgumentsAsyncResultsNullChannelAndSendFailure` | `callback(url, provider) → callback(null, provider)` | `TvFlutterRequestsCharacterizationTest.kt:25`: expected [(stream, TorBox)]; observed [(null, TorBox)] |
| m48 | `TvFlutterRequestsCharacterizationTest.movieMetadataPinsFilenameAsyncResultsNullChannelAndSendFailure` | `callback(imdbId) → callback(null)` | `TvFlutterRequestsCharacterizationTest.kt:41`: expected [tt123]; observed [null] |
| m49 | `TvFlutterRequestsCharacterizationTest.streamUrlsPinCandidateFilteringLabelsMessagesAndSynchronousFailurePaths` | `?: "Source" → ?: "Other"` | `TvFlutterRequestsCharacterizationTest.kt:80`: expected [([(one, Main), (two, Source), (three, Source)], Reason)]; observed [([(one, Main), (two, Other), (three, Other)], Reason)] |
| m50 | `TvFlutterRequestsCharacterizationTest.streamResultReportPinsFireAndForgetArgumentsAndSwallowsSendExceptions` | `"success" to success → "success" to !success` | `TvFlutterRequestsCharacterizationTest.kt:97`: expected {channelUrl=channel, url=stream, success=true}; observed {channelUrl=channel, success=false, url=stream} |
| m51 | `TvFlutterRequestsCharacterizationTest.quickPlayPinsFireAndForgetArgumentsNullChannelAndPropagatingSendException` | `"season" to season → "season" to season + 1` | `TvFlutterRequestsCharacterizationTest.kt:106`: expected {imdbId=tt123, season=2, episode=4}; observed {imdbId=tt123, season=3, episode=4} |
| m52 | `TvEpgRequestCharacterizationTest.epgPinsArgumentsAndAlwaysAnswersAsynchronouslyForEveryResultAndFailure` | `"archiveDisabled" to (entry.tvArchive == "0") → "archiveDisabled" to (entry.tvArchive != "0")` | `TvEpgRequestCharacterizationTest.kt:27`: expected {channelUrl=https://example.test/channel, includeSchedule=true, includeCatchupMetadata=false, archiveDisabled=true, archiveDurationDays=3}; observed {includeSchedule=true, channelUrl=https://example.test/channel, archiveDurationDays=3, includeCatchupMetadata=false, archiveDisabled=false} |
| m53 | `TvEpgRequestCharacterizationTest.epgDefaultDispatcherReadsCurrentEntryWhenCatchupArgumentIsOmitted` | `includeCatchupMetadata: Boolean = entry.isCurrent → includeCatchupMetadata: Boolean = !entry.isCurrent` | `TvEpgRequestCharacterizationTest.kt:46`: expected {channelUrl=https://example.test/channel, includeSchedule=false, includeCatchupMetadata=true, archiveDisabled=false, archiveDurationDays=null}; observed {includeSchedule=false, channelUrl=https://example.test/channel, archiveDurationDays=null, includeCatchupMetadata=false, archiveDisabled=false} |
| m54 | `TvEpgRequestCharacterizationTest.epgWatchdogFiresExactlyAtFortyFiveSecondsAndLateReplyCannotRedeliver` | `45_000 → 45_001` | `TvEpgRequestCharacterizationTest.kt:55`: expected [null]; observed [] |
| m55 | `TvEpgRequestCharacterizationTest.epgReplyBeforeDeadlineWinsAndWatchdogCannotRedeliver` | `delivered.compareAndSet(false, true) → true` | `TvEpgRequestCharacterizationTest.kt:65`: expected [{show=Now}]; observed [{show=Now}, null] |
| m56 | `TvIptvParsingCharacterizationTest.mapChannelOverloadFiltersByTypesAndKeepsRawIndexesAndNegativeMetadata` | `?.takeIf { it > 0 } → ?.takeIf { it >= 0 }` | `TvIptvParsingCharacterizationTest.kt:100`: expected …y(index=7, channelNumber=null, name=Zero, url=zero, lo…; observed …y(index=7, channelNumber=0, name=Zero, url=zero, lo… |
| m57 | `TvGuideDataCharacterizationTest.guideDataUpdatesOnlyPresentSectionsAndClearsLoadingOnEveryAnswer` | `(next["poster"] as? String)?.takeIf { it.isNotEmpty() } → (next["poster"] as? String)` | `TvGuideDataCharacterizationTest.kt:37`: expected …Title=null, nextUpPoster=null, nextUpYear=null, nextUp…; observed …Title=null, nextUpPoster=, nextUpYear=null, nextUp… |
| m58 | `TvIptvLoadPolicyCharacterizationTest.policyReadsLiveStateBetweenEveryInvocation` | `if (liveNow()) 20 else super.getMinimumLoadableRetryCount(dataType) → if (true) 20 else super.getMinimumLoadableRetryCount(dataType)` | `TvIptvLoadPolicyCharacterizationTest.kt:57`: expected 3; observed 20 |
| m59 | `TvEpgRequestCharacterizationTest.epgPinsArgumentsAndAlwaysAnswersAsynchronouslyForEveryResultAndFailure` | `if (channel == null) { ↵                 handler.post { deliver(null) } → if (channel == null) { ↵                 deliver(null)` | `TvEpgRequestCharacterizationTest.kt:36`: java.lang.AssertionError |
| m60 | `TvEpgRequestCharacterizationTest.epgWatchdogFiresExactlyAtFortyFiveSecondsAndLateReplyCannotRedeliver` | `delivered.compareAndSet(false, true) → true` | `TvEpgRequestCharacterizationTest.kt:56`: expected [null]; observed [null, {late=true}] |
| m61 | `TvFlutterRequestsCharacterizationTest.torrentRequestsPinArgumentsAsyncResultsNullChannelAndSendFailure` | `MainActivity.getAndroidTvPlayerChannel()?.invokeMethod( → if (MainActivity.getAndroidTvPlayerChannel() == null) { callback(null, null); return } ↵             MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(` | `TvFlutterRequestsCharacterizationTest.kt:31`: java.lang.AssertionError |
| m62 | `TvFlutterRequestsCharacterizationTest.movieMetadataPinsFilenameAsyncResultsNullChannelAndSendFailure` | `MainActivity.getAndroidTvPlayerChannel()?.invokeMethod( → if (MainActivity.getAndroidTvPlayerChannel() == null) { callback(null); return } ↵             MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(` | `TvFlutterRequestsCharacterizationTest.kt:46`: java.lang.AssertionError |
| m63 | `TvFlutterRequestsCharacterizationTest.streamResultReportPinsFireAndForgetArgumentsAndSwallowsSendExceptions` | `android.util.Log.w("AndroidTvPlayer", "reportIptvStreamResult failed: ${e.message}") → throw e` | `TvFlutterRequestsCharacterizationTest.kt:102`: reporting swallows messenger exceptions expected null, but was:<java.lang.IllegalStateException: messenger unavailable> |
| m64 | `TvFlutterRequestsCharacterizationTest.quickPlayPinsFireAndForgetArgumentsNullChannelAndPropagatingSendException` | `quick-play propagates send exceptions (exact text in catalog/patch)` | `TvFlutterRequestsCharacterizationTest.kt:111`: expected java.lang.IllegalStateException to be thrown, but nothing was thrown |
| m65 | `TvFormattingCharacterizationTest.menuRowPassesValuesAndCallbacksAndUsesRealDefaultDispatch` | `enabled: Boolean = true → enabled: Boolean = false` | `TvFormattingCharacterizationTest.kt:46`: expected Row(title=Default, value=null, selected=false, accent=false, enabled=true, swatch=null, adjustable=false, tag=null, onOk=null, onAdjust=null); observed Row(title=Default, value=null, selected=false, accent=false, enabled=false, swatch=null, adjustable=false, tag=null, onOk=null, onAdjust=null) |

### JVM and tooling evidence

Reused the clean original `junit/baseline-dcbd9aafe` archive and original
lint issue archive recorded before characterization: 323 JVM identities
(322 pass and the existing focus failure), zero dirty files; original lint
has 253 errors, 1,100 warnings and 175 UnsafeOptInUsageError issues.
Production/dependency/SDK inputs are unchanged, so these runs remain valid.

The full original-plus-tests run `junit/p2-step0-original-verified` and
current-tree baseline **`junit/p2-step0`** each contain **378 identities:
377 pass, the same existing focus failure, no skips**. Both runs have
stable before/after fingerprints and are complete, not aborted. Current
baseline tested `5bb66a997` with the 14 uncommitted test files that this
step commits, JBR 21.0.10; `test-file-hashes.json` pins their exact content.
Comparison against `baseline-dcbd9aafe`: **55 passing additions only**,
zero missing identities and zero changed original statuses. Original and
current identity/status maps match exactly. Gradle's exit 1 is solely the
known `TvSourceBrowserFocusTest` failure; the archive helper accepts the
complete evidence rather than masking it.

Commands: `python3 dev/tool/android_junit_evidence.py [--worktree
<detached-original>] run <label>`; `compare p2-step0 --against
baseline-dcbd9aafe`; `compare p2-step0 --against p2-step0-original-verified`.
Evidence: `p2/step0/{original,current}-full-baseline.log`,
`jvm-comparison.json`, comparison logs and the three `junit/` archives.
Final original focused run: 55/55 passing; raw log/XML in
`p2/step0/original-focused-final-assertions*`. The updated complete fixture
and all 32 checker tests pass; file-size and diff checks pass.

The detached original worktree is removed after these archives. No
production moves, ProGuard/lockfile edits, push, branch switch, device or
emulator work. Later phase-2 JVM gates compare against **`p2-step0`**.

## Phase 2 step 0b — URL guard order

Claude's original-code sample killed 15/16 mutations. The surviving d01
changed the whole-string question-mark guard to an ampersand guard. Four
new tests pin question marks in fragments, authority, credentials and ID;
ampersands and encoded delimiters; first query/fragment delimiters; suffixes
that occur only after those delimiters; and both query/fragment orders.
All 59 phase-2 characterization tests pass on original `dcbd9aafe`.

The two `substringBefore` operations in `isSegmentedStreamUrl` commute:
either order selects the prefix before the earliest delimiter. Swapping
them is equivalent and has no assertion-failing proof. Checking `?` on the
cleaned twin URL is observably different and is killed below. No behavior
fix was made.

Six named proof runs (five distinct source mutations) are assertion-killed
on the original, with fresh XML and source restoration between runs.
Evidence: `p2/step0b/mutation-catalog.json`, `run_mutations.py`,
`mutations/<ID>/`; d01 also runs against all 120 characterization identities
(including phase 1), failing only the two new twin tests, with no compile
errors/crashes (`d01-all-characterizations-result.json` and raw log/XML).

| ID | Named test (`TvIptvUrlGuardCharacterizationTest`) | Original mutation | Failing assertion |
|---|---|---|---|
| d01 | `twinRejectsQuestionMarksAnywhereBeforeRemovingTheFragment` | `if (url.contains('?')) return null` → `if (url.contains('&')) return null` | http://h/live/u/p/1.m3u8#x?y expected null, but was:<http://h/live/u/p/1.ts> |
| g02 | `twinRejectsQuestionMarksAnywhereBeforeRemovingTheFragment` | `if (url.contains('?')) return null` → `val clean = url.substringBefore('#')` | http://h/live/u/p/1.m3u8#x?y expected null, but was:<http://h/live/u/p/1.ts> |
| g03 | `twinPreservesAmpersandsAndEscapesAndUsesOnlyTheFirstFragment` | `val clean = url.substringBefore('#')` → `val clean = url.substringBeforeLast('#')` | expected:<http://h/live/u/p/1.ts> but was:<null> |
| g04 | `twinPreservesAmpersandsAndEscapesAndUsesOnlyTheFirstFragment` | `if (url.contains('?')) return null` → `if (url.contains('&')) return null` | h/live/u&x/p/1 expected:<http://h/live/u&x/p/1.ts> but was:<null> |
| g05 | `segmentedPathsStopAtTheFirstQuestionMarkEvenWithLaterSuffixes` | `val path = url.substringBefore('?').substringBefore('#').lowercase()` → `val path = url.substringBeforeLast('?').substringBefore('#').lowercase()` | http://h/a.M3U8?first.ts?last expected:<true> but was:<false> |
| g06 | `segmentedPathsStopAtTheFirstFragmentEvenWhenItContainsAQuestion` | `val path = url.substringBefore('?').substringBefore('#').lowercase()` → `val path = url.substringBefore('?').substringBeforeLast('#').lowercase()` | http://h/a.M3U8#first.ts#last expected:<true> but was:<false> |

For g02 the complete replacement moves the guard after fragment removal
and checks `clean`; the catalog retains its exact two-line before/after.
g04 repeats d01 against the independent ampersand-preservation assertion.

Full JVM baseline `p2-step0b`: **382 identities, 381 pass, the unchanged
known focus failure, zero skips**. Versus `p2-step0`, all 378 prior statuses
match exactly and only four passing identities are added. The input
fingerprint is stable (HEAD `b840bf878` plus the one new test file); JBR
21.0.10. Evidence: `junit/p2-step0b/`, `p2/step0b/baseline-additions.json`.
The detached mutation worktree was removed.

## Phase 2 step 1 — production moves and retargets

The manifest moves 54 complete subtrees to 12 files, retaining the same
package and unqualified production call sites. Exactly three declaration
opt-ins, four relocated constants, the policy constructor supplier and the
single `setupPlayer` patch match the approved manifest. Kotlin PSI compares
all 2,839 original declarations: zero differences beyond declared edits.
Multiline comment/string tokens and newlines are byte-preserved; only
leading code indentation changes. All 32 checker self-tests pass, including
the complete phase-1 fixture and every required negative.

Only `TvPlayerOriginalAccess.kt` is retargeted in tests. `callTyped` selects
the facade's exact static signature for moved functions (including both
channel overloads); `callDefault` uses the real static `$default` dispatcher
without the former activity receiver. Existing assertions remain intact.
Its original-name selectors map as follows:

| Original activity members | New owner |
|---|---|
| `fun classifyIptvError(PlaybackException)`, `class IptvLiveLoadErrorPolicy` | `IptvLoadErrorPolicyKt` (functions/constants); top-level classes in `IptvLoadErrorPolicy.kt` |
| `fun parseIptvSources(JSONArray?)`, `fun parseIptvLists(JSONArray?)`, `fun parseStringList(JSONArray?)`, `fun parseIptvChannels(JSONArray)`, `fun parseIptvChannels(List<*>)`, `fun iptvChannelEntry(Int,Int?,String,String,String?,String?,String,Int,String?,String?,Boolean,String?,String?,Int?,Int?,Boolean?,String?,Int?,Long,Map<String, String>)` | `IptvPayloadParsingKt` (functions/constants); top-level classes in `IptvPayloadParsing.kt` |
| `fun isSegmentedStreamUrl(String)`, `fun xtreamTsTwin(String)`, `fun sanitizeRecordingName(String)`, `fun recordingTimestamp()` | `IptvRecordingUrlRulesKt` (functions/constants); top-level classes in `IptvRecordingUrlRules.kt` |
| `fun isIptvSeriesSentinel(IptvChannelEntry)`, `fun currentIptvStartOverProgramme(IptvChannelEntry)`, `fun formatIptvRemaining(Long)`, `fun adoptIptvEpg(IptvChannelEntry,IptvChannelEntry)`, `fun isStremioIptvUrl(String)`, `fun iptvQualityFromLabel(String)` | `IptvEntryRulesKt` (functions/constants); top-level classes in `IptvEntryRules.kt` |
| `fun buildNowPlayingText(StremioTvGuideChannel)`, `fun updateStremioTvGuideChannelData(StremioTvGuideChannel,Map<*, *>)` | `StremioTvGuideDataKt` (functions/constants); top-level classes in `StremioTvGuideData.kt` |
| `fun languageOfOverride(TrackSelectionOverride?)`, `fun buildAudioTrackLabel(Format)`, `fun buildSubtitleTrackLabel(Format)`, `fun isSearchSubtitleOption(String)`, `fun isLoadingSubtitleOption(String)`, `fun isExternalSubtitleOption(String)`, `fun isSideRenderableSubtitle(String)`, `property SEARCH_SUBTITLE_LABEL`, `property EXTERNAL_SUBTITLE_PREFIX` | `TvTrackLabelsKt` (functions/constants); top-level classes in `TvTrackLabels.kt` |
| `fun parseSubtitleCatalogResults(Any?)`, `fun resolveSeasonEpisodeForSubtitle(PlaybackItem)`, `fun parseSeasonEpisodeFromTitle(String)`, `fun buildSubtitleSearchInitialQuery(PlaybackItem)`, `fun buildManualSubtitleDisplayLabel(SubtitleCatalogResult,String,Int?,Int?)` | `SubtitleSearchQueryKt` (functions/constants); top-level classes in `SubtitleSearchQuery.kt` |
| `fun spellNumber(Int?)`, `fun getAcceleratedSeekStep(Int)`, `fun formatTime(Long)` | `TvPlayerFormattingKt` (functions/constants); top-level classes in `TvPlayerFormatting.kt` |
| `fun mrow(String,String?,Boolean,Boolean,Boolean,Int?,Boolean,String?,(() -> Unit)?,((Int) -> Unit)?)` | `UnifiedMenuRowsKt` (functions/constants); top-level classes in `UnifiedMenuRows.kt` |
| `fun androidDecoderStatus(String)`, `fun buildProtectedMediaOrigins(List<PlaybackItem>)`, `fun originKey(Uri)`, `fun isPikPakPlaybackItem(PlaybackItem?)`, `fun diagnosticProvider(String?)`, `fun startupLog(String,Boolean)`, `property STARTUP_FAILOVER_LOG_TAG`, `property PROVIDER_PIKPAK` | `TvStartupDiagnosticsKt` (functions/constants); top-level classes in `TvStartupDiagnostics.kt` |
| `fun rebuildNavigationMaps(PlaybackPayload,String)` | `PlaylistNavigationMapsKt` (functions/constants); top-level classes in `PlaylistNavigationMaps.kt` |
| `fun requestStreamFromFlutter(PlaybackItem,Int,(String?, String?) -> Unit)`, `fun requestMovieMetadataFromFlutter(PlaybackItem,Int,(String?) -> Unit)`, `fun requestIptvEpg(IptvChannelEntry,Boolean,Boolean,(Map<*, *>?) -> Unit)`, `class IptvStremioCandidate`, `fun requestIptvStreamUrls(String,String?,(List<IptvStremioCandidate>, String?) -> Unit)`, `fun reportIptvStreamResult(String,String?,Boolean)`, `fun requestQuickPlayNextEpisode(String,Int,Int)` | `TvPlayerFlutterRequestsKt` (functions/constants); top-level classes in `TvPlayerFlutterRequests.kt` |

The old binary selector `AndroidTvTorrentPlayerActivity$IptvStremioCandidate`
now selects `IptvStremioCandidate`, preserving the exact-class assertion and
field/getter checks. The old typed inner-policy constructor selector now
constructs `IptvLiveLoadErrorPolicy(Function0)` with fresh activity field
reads. Additional helper assertions check zero supplier invocations during
construction, then both methods on a separate invoking thread. Existing
per-invocation live/non-live/invalid-index assertions still exercise that
same policy instance. The production supplier remains exactly the manifest
expression; the reflection and thread probe exist only in tests.

Dart anchors stay at their existing activity path. No moved signature is an
anchor; `sendProgress` → `commitStartupCandidate` retains its manual-source
guards after removing unrelated helpers. All four source-text suites retain
45 identities, 44 pass and the same existing profile-source failure, with
no changed statuses vs the observed phase-1 gate. `NativeAudioRoutingTest`
retains its unchanged Media3 builder assertion and passes in the full JVM
run. No Dart edits or weakened assertions.

The activity decreases 19,961 → 19,017 lines (944 removed); extracted files
are 7–233 lines. `check_file_sizes.py --update` lowers only this activity's
ratchet; pre-existing unrelated shrinkage entries remain unchanged. Size
and diff checks pass. `compileDebugKotlin` and unit-test compilation pass
with no new warning identities. Clean `junit/p2-gate` has exactly the same
382 identity/status pairs as `p2-step0b` (381 pass, known focus failure, no
skips), with a stable input fingerprint. Evidence under `p2/step1/`.
Release, mapping, lint and full Flutter gate evidence follow separately.

## Phase 2 gate — parity evidence and environment limitation

Executed on Step 1 `0607b0b60` (production inputs identical to the clean
JVM gate run archived before that commit). No independent review was
performed; Claude runs the separate review session.

| Check | Result | Evidence |
|---|---|---|
| Kotlin PSI checker / self-tests | 2,839 declarations classified; zero undeclared differences; all 32 self-tests pass, including the unchanged phase-1 fixture | `p2/step1/checker-final.log`, `checker-self-tests.log` |
| Kotlin compile / size | Debug production and test compilation pass; no new warning identities. Activity 19,017 lines, new files 7–233, size ratchet passes | `p2/step1/compile-final.log`, `kotlin-warning-comparison.json`, `sizes.log` |
| Clean JVM identities | All 382 identity/status pairs match `p2-step0b`: 381 pass, known focus failure, zero skips; stable input fingerprint | `junit/p2-gate/`, `p2/step1/jvm-exact-status-comparison.json` |
| Dart source guards | All 45 identity/status pairs match the phase-1 gate: 44 pass, existing profile-source failure | `p2/step1/dart-source-guards*` |
| Android lint | Exact issue multiset unchanged: 1,353 issues, 253 errors/1,100 warnings, all 175 `UnsafeOptInUsageError` identities retained | `p2/gate/lint-comparison.json`, raw XML/TXT/HTML, `compare_lint.py` |
| Release build | `flutter build apk --release` succeeds; no install. APK SHA/provenance archived | `p2/gate/release-build.log`, `release-provenance.json` |
| R8 | All 12 source destinations, 18 compiled classes (including 12 `…Kt` facades, policy, candidate and four request-result classes), 102 members retain identity names. 87 explicit mappings and 15 omitted mappings verified directly in APK DEX. Three negative controls pass | `p2/gate/check_mapping.py`, `mapping-result.json`, `moved-bytecode-inventory.json`, release mapping/configuration/seeds/usage |
| Decoder verification | **Pending-environment**: script exits 1 with the same phase-1 fallback-bundle failure; all three ABI `libmpv` SHA-256 values exactly match phase 1 | `p2/gate/decoder.log`, `decoder-provenance.json`, per-ABI FFmpeg configuration |
| Full Flutter suite | All **12,855 identity/status pairs exactly match phase 1**: 12,794 successes, 13 failures, 28 errors, 20 skips. No new failures, missing identities, changed statuses or additions; tested tree clean/stable and Flutter 3.44.8/Dart 3.12.2 unchanged | `p2/gate/flutter-gate.*`, `flutter-comparison.log`, `flutter-exact-status-comparison.json` |

Lint locations are resolved to their original PSI declaration selectors,
with unchanged source snippets and columns after indentation normalization;
all other file/line/column locations stay exact. Relocations do not remove
any rule, message or multiplicity. Both lint commands exit 1 for the same
pre-existing issues; lint parity passes, not a clean-lint claim.

Additional `flutter analyze --no-pub` produces 1,758 diagnostics vs 1,767
in the phase-1 archive. A literal-path comparison initially flags four
generated release `pubspec.yaml` diagnostics. The helper's two explicit
`--relocate` pairs match each against an identical existing diagnostic in
the generated debug copy; no added diagnostic remains. The nine removed
entries are two generated unit-test asset diagnostics and seven duplicate
source/package diagnostics. All repository Dart sources are byte-identical
to the phase-1 gate; no broad location ignoring or allowlist change. See
`p2/gate/analyze-generated-relocation-comparison.log` and `analyze-summary.json`.
No Dart formatting was needed because no Dart source changed.

Decoder script stops on arm64's missing nine subtitle decoders and three
auto-sync filters. The independent APK byte/hash/configuration inventory
confirms the identical fallback on arm64-v8a, armeabi-v7a and x86_64. The
patched bundle is unavailable in this local environment; no decoder,
dependency or ProGuard changes are made to bypass it. This existing
phase-1 limitation carries forward and the complete decoder gate is not
claimed passed.

Lockfile, ProGuard and phase-1 manifest hashes match the protected-input
archive. The original mutation worktree is removed. No push, branch switch,
device/emulator interaction or bug fix. Gate summary:
`p2/gate/execution-summary.json`. **Stopped after phase-2 moves and gate
checks; Claude's separate review and patched-bundle verification remain.**

---

## Phase 3 inventory (stateful feature feasibility, at `dcbd9aafe`; re-measure on `ec365eb80`)


Source: `android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt` at
`dcbd9aafe` (19,961 lines; class header 136, companion 19914–19960). Read-only survey. Line numbers
are current (lines < 10602 are unchanged from the pre-phase-1 survey; later ones shifted).
References were found with a word-boundary scan that resolves each hit's enclosing class member,
then checked by hand. "Patch" means one token-level edit in a retained activity declaration
(`foo` → `ctl.foo`), the edit the checker would record as `patched`.

Phase-2 assumptions (from the `Phase 2 inventory` on `refactor/tvplayer-p2`, b840bf878; the
section is **not** in the deps doc at `dcbd9aafe`): top-level by phase 3 are
`isSegmentedStreamUrl`, `xtreamTsTwin`, `sanitizeRecordingName`, `recordingTimestamp` (group C),
`isPikPakPlaybackItem` plus `internal const val PROVIDER_PIKPAK` (group J), `startupLog`, and
`mrow`. Phase 2 explicitly leaves these in the activity because they are almost pure:
`dp`, `releaseScreenForSleep`, `holdScreenForPlayback`, `fadeInNextOverlay`, `hideNextOverlay`,
`isCurrentIptvSegmented`, `engineRecordableUrl`, `isSchedulableStreamUrl`,
`engineTaskIdForCurrentChannel` and `recordingResourceFor`. `SkipSegmentRequest` and
`SleepTimerMode` are pure but are deferred to phase 3, to move with their features.

### Cross-cutting constraints (apply to every feature)

- **`::prop.isInitialized` cannot be qualified.** It only compiles for properties in the same
  lexical scope, so `host::x.isInitialized` is illegal. Every such check either keeps its lateinit
  in the same class or becomes a host getter, which is a non-trivial substitution. Moved-code
  sites: 6879 `::startupGateStatus`, 6893 `::pikPakReactivationIndicator`, 8165/8415
  `::skipSegmentButton`, 8326 `::seekFeedbackManager`. 8397/8403 `::playerView` stay, because
  their functions stay.
- **Ambiguous `this`.** In 6819, 6839, 6851 and 6864, `this` is the polling `object : Runnable`,
  and so is 8740 (`upNextTicker`). It must **not** be substituted. Every other `this` in the moved
  code is the Activity/Context. Scope functions in the moved code have no receiver ambiguity
  (checked: recording's only `apply` is `Intent(this, …).apply {}`, where `this` precedes the
  receiver).
- **Inherited statics and members.** `MODE_PRIVATE` (9427), `isFinishing`, `isDestroyed`,
  `runOnUiThread`, `startService`, `getSharedPreferences`, `findViewById`, `currentFocus`,
  `resources` and `window` need `activity.` substitutions. Labels such as `return@runOnUiThread`
  survive `activity.runOnUiThread {`.
- **Companion constants used by only one feature** move with it as file-private top-level
  constants. A declared companion-member move:
  - Up Next: `UP_NEXT_THRESHOLD_MS` 19940, `UP_NEXT_MIN_DURATION_MS` 19941, `UP_NEXT_TICK_MS` 19942.
  - Skip: `MAX_SKIP_SEGMENT_CACHE_ENTRIES` 19951, `IMDB_ID_REGEX` 19952. `IMDB_ID_REGEX` is used
    only at 8147.
  - PikPak: `PIKPAK_MAX_RETRIES` 19956, `PIKPAK_METADATA_TIMEOUT_MS` 19957,
    `PIKPAK_BASE_DELAY_MS` 19958, `PIKPAK_MAX_DELAY_MS` 19959, plus the comment at 19954.
    `PROVIDER_PIKPAK` already goes top-level in phase 2.
- **Reflection and name mangling.** Kotlin mangles the JVM names of `internal` *members*. A test
  that reflects a moved member by simple name must target a `private` member or a public member of
  an `internal class`; it must not target an `internal fun`. This matters for the PikPak retargets.
- **Construction order.** The Handlers and the skip scope are property initializers created at
  activity construction. Declare each controller as a property where its field block was, so
  initializer order and creation time stay as they are. The checker treats the removed fields as
  moved and the new property as a declared new declaration. Implement host interfaces as an
  `object :` inside that property initializer. Making the activity implement them would patch the
  class header.

---

### 1. Sleep timer (rank 2)

**Owned state** (moves):

| line | name | type / initializer |
|---|---|---|
| 1268 | `SleepTimerMode` | `private enum class { OFF, COUNTDOWN, END_OF_ITEM }` → top-level `internal enum` (unqualified uses then resolve unchanged) |
| 1269 | `sleepTimerMode` | `= SleepTimerMode.OFF` |
| 1270 | `sleepTimerDeadlineElapsedMs` | `= 0L` |
| 1271 | `sleepTimerHandler` | `val = Handler(Looper.getMainLooper())` |
| 1272 | `sleepTimerRunnable` | `Runnable? = null` |
| 1273 | `sleepTimerMinuteOptions` | `val = listOf(15, 30, 45, 60, 90)` |

The banner comment 1261–1267 moves with the block.

**Not cleanly ownable:** `sleepStopLatched` (1275–1282, `= false`).
- Written at: 1682 and 1717 (playbackListener), 4591 (playItem), 7417 (togglePlayPause), 8382
  (fireSleepTimer).
- Read at: 414 (iptvLiveRecoveryEligible), 582 (onIptvTwinTrialTimeout), 4584 (playItem), 4748
  (discoverProtectedMime), 4778 (startPlayback), 5413 (shuffleAttemptOwned), 18874 (onStart).
- It stays in the activity. Moving it would cost 11 patches in playback-core code.

**Owned functions:**
- Moved: `sleepTimerMinutesLeft@8336–8340`, `sleepTimerValueLabel@8342–8346`,
  `startSleepCountdown@8348–8359`, `armSleepAtEndOfItem@8361–8365`, `cancelSleepTimer@8367–8373`,
  and `fireSleepTimer@8380–8387` with its KDoc from 8375. The banner is at 8333.
- **Stay:** `releaseScreenForSleep@8395–8398` and `holdScreenForPlayback@8401–8404`. They use
  `window` and `::playerView.isInitialized`, and playbackListener calls them at 1683, 1718 and 1805.
- Total ≈ 13 field lines + 55 function lines ≈ **68 lines**.

**Inbound coupling** (13 patches in 4 declarations):

| line | enclosing | ref | kind |
|---|---|---|---|
| 414 | iptvLiveRecoveryEligible | `sleepTimerMode` | read |
| 1680 | playbackListener (val@1499) | `sleepTimerMode` | read |
| 1681 | playbackListener | `cancelSleepTimer()` | call |
| 1715 | playbackListener | `sleepTimerMode` | read |
| 1716 | playbackListener | `cancelSleepTimer()` | call |
| 15422 | umPlaybackModel@15419 | `sleepTimerValueLabel()` | call |
| 15429 | umPlaybackModel | `sleepTimerMode` | read |
| 15430 | umPlaybackModel | `cancelSleepTimer(announce = true)` | call |
| 15433 | umPlaybackModel | `sleepTimerMinuteOptions` | read |
| 15434 | umPlaybackModel | `startSleepCountdown(minutes)` | call |
| 15442 | umPlaybackModel | `sleepTimerMode` | read |
| 15443 | umPlaybackModel | `armSleepAtEndOfItem()` | call |
| 19103 | onDestroy | `cancelSleepTimer()` | call |

`SleepTimerMode.X` at 414, 1680, 1715, 15429 and 15442 needs no patch once the enum is top-level.
umPlaybackModel moves in phase 4; whichever phase runs second re-patches it.

**Outbound:**
- State/actions, all in `fireSleepTimer`: `sleepStopLatched` (write, 8382),
  `sendProgress(completed = false)` (8383; named argument, so the host method must name its
  parameter `completed`), `player?.pause()` (8384), `releaseScreenForSleep()` (8385).
- Android: Toast context `this` at 8358, 8364, 8372 and 8386; the handler is owned.

**Timers:**
- `sleepTimerHandler` is the only timer. `cancelSleepTimer` removes its callbacks.
- Teardown: only `onDestroy@19103`, after `RecordingRegistry.removeListener` 19100 and before
  `finalizeIptvRecordingIfActive` 19107. Nothing in onPause/onStop.
- The fire order is cancel → latch → sendProgress → pause → release screen → toast. It must stay.

**Tests:** none reflective. No Dart anchors (the Dart `SleepTimerMode` is unrelated).

**Proposed shape:**
```kotlin
internal class TvSleepTimerController(private val activity: AppCompatActivity, private val host: Host) {
    interface Host {
        var sleepStopLatched: Boolean
        val player: Player?
        fun sendProgress(completed: Boolean)
        fun releaseScreenForSleep()
    }
}
```

**Substitutions (8):**
- `this` → `activity` ×4.
- In `fireSleepTimer` only: `sleepStopLatched` → `host.sleepStopLatched`, `sendProgress` →
  `host.sendProgress`, `player` → `host.player`, `releaseScreenForSleep` →
  `host.releaseScreenForSleep`.

**Activity patches: 13. Risk: low.**

Note: the deps doc's earlier idea, that the controller owns `sleepStopLatched`, is not
recommended, because it is read on 7 playback paths.

---

### 2. Skip segments (intro/credits) (rank 1)

**Owned state** (moves; the comment block 1240–1242 travels with it):

| line | name | type / initializer |
|---|---|---|
| 1243–1250 | `SkipSegmentRequest` | `private data class(providerId, imdbId, season, episode, durationSeconds, key)`; file-private in the destination |
| 1251 | `skipSegmentScope` | `val = CoroutineScope(Dispatchers.Main + SupervisorJob())` |
| 1252 | `skipSegmentFetchJob` | `kotlinx.coroutines.Job? = null` |
| 1253 | `skipSegmentFetchGeneration` | `= 0` |
| 1254 | `loadedSkipSegmentKey` | `String? = null` |
| 1255 | `loadingSkipSegmentKey` | `String? = null` |
| 1256 | `skipSegments` | `= TvSkipSegments.EMPTY` |
| 1257 | `activeSkipSegment` | `TvSkipSegment? = null` |
| 1258 | `skipFocusOfferedKey` | `String? = null` |
| 1259 | `skipSegmentCache` | `val = mutableMapOf<String, TvSkipSegments>()` (bounded at 64, evicts the first key) |

**Stay in the activity:**
- `skipSegmentButton` (168, lateinit `AppCompatButton`). It is bound at 2523, and
  dispatchKeyEvent@7217 does `::skipSegmentButton.isInitialized && currentFocus == skipSegmentButton`,
  which cannot be qualified.
- `skipSegmentsEnabled` (848) and `skipSegmentProviderId` (849). loadPlayerDefaults writes them
  (16373, 16379) and logs them (16385). They are player defaults (phase 4).

**Owned functions:**
- `currentSkipSegmentRequest@8135–8162`, `updateSkipSegmentState@8164–8197`,
  `ensureSkipSegments@8199–8255`, `presentSkipSegment@8257–8305`, `skipActiveSegment@8307–8331`,
  `resetSkipSegmentState@8406–8416`. The last is separated from the others by the sleep block.
- ≈ 20 + 197 + 11 + 2 constant lines ≈ **230 lines**.

**Inbound** (8 patches in 4 declarations):

| line | enclosing | ref | kind |
|---|---|---|---|
| 2524 | bindViews | `skipActiveSegment()` (click lambda) | call |
| 4612 | playItem | `resetSkipSegmentState()` | call; must stay right after hideUpNextCard 4611 |
| 7677 | updateSeekbarProgress | `updateSkipSegmentState(currentPosition, duration)` | call |
| 19154 | onDestroy | `skipSegmentFetchGeneration++` | write |
| 19155–19156 | onDestroy | `skipSegmentFetchJob?.cancel()`, `= null` | call / write |
| 19157 | onDestroy | `skipSegmentScope.cancel()` | call |
| 19158 | onDestroy | `skipSegmentCache.clear()` | call |

A single `destroy()` member would cut the 5 onDestroy patches to 1, but it is a new declaration and
not verbatim. Prefer the 5 qualified patches.

**Outbound:**
- State (host):
  - Read-only: `skipSegmentsEnabled` 8136; `skipSegmentProviderId` 8137, 8155, 8160; `isIptvMode`
    8138; `payload` 8145; `currentIndex` 8148; `hasEverBeenReady` 8175.
  - `upNextVisible` 8195 and 8295. This is Up Next state: host getter.
  - `player` 8241, 8252, 8308.
  - `controlsMenuVisible` 8282, 8292; `playlistVisible` 8293; `seekbarVisible` 8294.
  - `subtitlePanel` 8296, `unifiedMenu` 8297, `sourceBrowser` 8298, `syncOverlay` 8299,
    `linePickerOverlay` 8300.
  - `releaseResumeHold()` 8324.
  - `seekFeedbackManager` 8326 (`::isInitialized`) and 8328.
- Views/Android: `skipSegmentButton` 8165 (`::isInitialized`), 8258, 8415 (`::isInitialized`);
  `currentFocus` and `playerView.requestFocus()` 8262; `resources.displayMetrics.density` 8283.
- Pure: `TvSkipSegmentClients`, `TvSkipSegments`, `C.TIME_UNSET`, `Locale`.

**Timers:**
- `skipSegmentScope` (Main + SupervisorJob) and `skipSegmentFetchJob`.
- `button.post {}` at 8303 and the ViewPropertyAnimators at 8263, 8276, 8279 and 8288 are
  **not** cancelled on destroy. Keep that as is.
- Teardown: only onDestroy 19154–19158, after `subtitleScope.cancel()` 19148 and before
  `progressHandler.removeCallbacksAndMessages` 19161.
- The staleness guard is the generation check at 8240 plus the recomputed key check at 8242.

**Tests:** none (the Dart `skip_segment_*` tests target the Flutter service).

**Proposed shape:**
```kotlin
internal class TvSkipSegmentController(private val activity: AppCompatActivity, private val host: Host) {
    interface Host {
        val skipSegmentButtonBound: Boolean            // activity: ::skipSegmentButton.isInitialized
        val skipSegmentButton: AppCompatButton
        val skipSegmentsEnabled: Boolean; val skipSegmentProviderId: String
        val isIptvMode: Boolean; val payload: PlaybackPayload?; val currentIndex: Int
        val hasEverBeenReady: Boolean; val player: ExoPlayer?; val playerView: PlayerView
        val controlsMenuVisible: Boolean; val playlistVisible: Boolean; val seekbarVisible: Boolean
        val upNextVisible: Boolean
        val subtitlePanel: SubtitleSettingsPanelController?; val unifiedMenu: UnifiedMenuController?
        val sourceBrowser: TvSourceBrowserController?; val syncOverlay: SubtitleSyncOverlay?
        val linePickerOverlay: SubtitleLinePickerController?
        val seekFeedbackManagerBound: Boolean; val seekFeedbackManager: SeekFeedbackManager
        fun releaseResumeHold()
    }
}
```
Verify the exact view and controller types against the field declarations at 1197–1201.

**Substitutions:** ≈ 34 `host.`/`activity.` token edits.
- The two `::skipSegmentButton.isInitialized` checks become `host.skipSegmentButtonBound`.
- `::seekFeedbackManager.isInitialized` becomes `host.seekFeedbackManagerBound`.
- `currentFocus` and `resources` become `activity.…`.

The host surface is wide, but it is all read-only except `releaseResumeHold()`.

**Activity patches: 8. Risk: medium-low.** The async generation guard and per-item reset ordering
are already well delimited.

---

### 3. Up Next card (rank 3)

**Owned state** (moves; the banner at 163 moves too):

| line | name | type / initializer |
|---|---|---|
| 164 | `upNextCard` | lateinit `View` |
| 165 | `upNextPoster` | lateinit `android.widget.ImageView` |
| 166 | `upNextTitle` | lateinit `TextView` |
| 167 | `upNextCountdown` | lateinit `TextView` |
| 169 | `upNextVisible` | `= false` |
| 170 | `upNextTargetIndex` | `Int? = null` |
| 171 | `upNextDismissedForIndex` | `= -1` |
| 172 | `upNextHandler` | `val = Handler(Looper.getMainLooper())` |

The field run is interleaved with `skipSegmentButton@168`, which stays. There are no
`::isInitialized` checks on the Up Next views.

**Owned functions:**
- `maybeShowUpNext@8691–8711`, `upNextTicker` (val object Runnable) `@8713–8742`,
  `showUpNextCard@8744–8769`, `triggerUpNext@8771–8777`, `dismissUpNext@8779–8782`,
  `hideUpNextCard@8784–8796`. The banner is at 8672–8674.
- **Keep `isCleanPlaybackState@8677–8687` in the activity.** It is a cross-cluster predicate (11
  flags, including `nextOverlay` and `pikPakReactivationIndicator`) and becomes a host method.
- ≈ 9 + 106 + 3 constant lines ≈ **118 lines**.

**Inbound** (12 patches; 14 if skip is still in the activity):

| line | enclosing | ref | kind |
|---|---|---|---|
| 2519–2522 | bindViews | `upNextCard/Poster/Title/Countdown =` | write ×4 |
| 1454 | progressRunnable (val@1451) | `maybeShowUpNext()` | call, every 5 s |
| 4611 | playItem | `hideUpNextCard()` | call (per-item reset; triggerUpNext depends on it) |
| 5509 | playShowShuffle | `hideUpNextCard()` | call |
| 7191 | dispatchKeyEvent | `upNextVisible` | read |
| 7194 / 7198 / 7202 | dispatchKeyEvent | `triggerUpNext()`, `dismissUpNext()`, `hideUpNextCard()` | call ×3 |
| 19135 | onDestroy | `upNextHandler.removeCallbacksAndMessages(null)` | call |
| (8195, 8295) | updateSkipSegmentState, presentSkipSegment | `upNextVisible` | read; 0 if skip moved first (host getter) |

**Outbound:**
- State/actions (host):
  - `continuousShuffleEnabled` 8693, 8705; `canShuffleWholeShow()` 8693.
  - `isIptvMode`, `isStremioTvMode` 8694.
  - `currentIndex` 8695, 8708, 8780; `isCleanPlaybackState()` 8696, 8722.
  - `player` 8697, 8715; `pickShuffleIndex()` 8706; `getNextPlayableIndex()` 8708.
  - `payload` 8745.
  - `isAutoAdvancing` (**write**, 8775); `playItem(target)` 8776.
- Android: Glide `with(this)` 8756 (activity). `this` at 8740 is the Runnable and is not
  substituted.

**Timers:**
- `upNextHandler` with `upNextTicker`, removed in showUpNextCard 8767 and hideUpNextCard 8785.
- Teardown: only onDestroy 19135, after `bufferingHandler.removeCallbacksAndMessages` 19132 and
  before the metadata-receiver unregister. The card animators are not cancelled; keep that.

**Tests:** `test/android_tv_auto_advance_resume_test.dart:39–51` uses
`_between('private fun triggerUpNext()', 'private fun dismissUpNext()')` on the activity file. It
asserts that `isAutoAdvancing = true` comes before `playItem(target)`.
- **Retarget** it to the new file. Both anchors change if the functions become non-private:
  activity calls triggerUpNext and dismissUpNext, so they lose `private`.
- With `host.` prefixes the asserted substrings still match.
- No reflection tests.

**Proposed shape:**
```kotlin
internal class TvUpNextController(private val activity: AppCompatActivity, private val host: Host) {
    interface Host {
        val player: ExoPlayer?; val payload: PlaybackPayload?; val currentIndex: Int
        val continuousShuffleEnabled: Boolean; val isIptvMode: Boolean; val isStremioTvMode: Boolean
        var isAutoAdvancing: Boolean
        fun isCleanPlaybackState(): Boolean
        fun canShuffleWholeShow(): Boolean
        fun pickShuffleIndex(): Int?
        fun getNextPlayableIndex(i: Int): Int?
        fun playItem(index: Int)   // playItem has defaulted params; the host wrapper must call playItem(index) exactly
    }
}
```

**Substitutions:** ≈ 17 `host.` edits, plus `this` → `activity` ×1 (8756).

**Activity patches: 12 (+2 without skip). Risk: medium.** The ticker races playItem, and there is
1 Dart retarget.

---

### 4. Status pill + auto-sync pill (rank 4 for the status pill; auto-sync pill: defer to phase 4)

### 4a. Status pill

**Owned state:**
- `statusPill` 1296, `TextView? = null`.
- `statusPillHideRunnable` 1297, `val = Runnable { hideStatusPill() }`.

**Functions:**
- `ensureStatusPill@15992–16015`, `showStatusPill@16017–16027`,
  `showStatusPillTransient@16030–16033` (1400 ms), `hideStatusPill@16035–16043`.
- With the banner 15988–15990: ≈ **58 lines**.

**Inbound** (40 call sites in 18 declarations):
- `showStatusPill`: 15815 (loadStremioSubtitle), 17762 (onStremioSourceSelected).
- `showStatusPillTransient` (31 calls):
  - 1821 (playbackListener) and 5506 (playShowShuffle).
  - onExternalSubtitleLoaded: 15839, 15903.
  - requestEpisodeFetch: 16791, 16796, 16811, 16833, 16840.
  - requestAdjacentEpisodeFetch: 16859, 16865, 16885, 16891, 16921, 16928.
  - commitManualSourceCandidate: 17145. failManualSourceCandidate: 17203.
  - watchSourceSwitchOutcome: 17649, 17659.
  - resolveStremioSourceViaFlutter: 17827, 17840, 17852, 17863.
  - resolveSourceToPlaylistViaFlutter: 17917, 17930, 17942, 17953.
  - failMoreTorrentSources: 18179.
  - switchToSourcePlaylist: 18248, 18266, 18293.
- `hideStatusPill` (7 calls): 15931 (stopExternalSubtitleRendering), 17205
  (failManualSourceCandidate), 17342 (commitStartupCandidate), 17420 (failStartupCandidate), 17640
  and 17656 (watchSourceSwitchOutcome), 17684 (dropStaleSourceSwitchFeedback).

**Outbound:**
- Android only: `this` 15994; `dp(` ×8 at 16000, 16001, 16003, 16004 and 16010; `findViewById`
  16012.
- Borrowed `externalSubtitleHandler` at 16018, 16032 and 16036. It is shared with the subtitle
  ticker and the auto-sync ladder/verify.

**Timers:**
- The hide runnable is posted on the borrowed `externalSubtitleHandler`. It is cleared only by
  onDestroy's `externalSubtitleHandler.removeCallbacksAndMessages(null)` @19195, which comes after
  player release. The controller must not own or clear that handler.
- The pill view is never removed, and its animators are not cancelled.

**Tests:** none.

**Shape:** `TvStatusPill(activity: Activity, handler: Handler /*borrowed*/, dp: (Int) -> Int)`.
- Substitutions: `this` → `activity` ×1, `findViewById` → `activity.findViewById` ×1,
  `externalSubtitleHandler` → `handler` ×3, `dp(` → `dp(` (lambda name kept) or `host.dp(` ×8.

**Activity patches: 40.** Alternatively keep three one-line delegating members in the activity:
**3 patched declarations, 0 call-site patches**.
**Recommendation:** use the delegating members. The feature is tiny, so if delegating members are
rejected as non-verbatim, defer it. **Risk: low** (UI only).

### 4b. Auto-sync pill (UI for the auto-sync engine, cluster C5)

**Owned state:**
- `autoSyncPill` 1302 (`LinearLayout? = null`), `autoSyncPillRing` 1303
  (`AutoSyncRingView? = null`), `autoSyncPillLabel` 1304 (`TextView? = null`).
- `autoSyncPillResultShowing` 1305 (`= false`; **write-only**, never read),
  `autoSyncPillWindowActive` 1306 (`= false`), `autoSyncPillAnnounceShowing` 1307 (`= false`).
- `autoSyncPillAnnounceDismissRunnable` 1310–1315 (val Runnable),
  `autoSyncCardHideRunnable` 1316 (val Runnable).
- The comment block 1299–1301 moves too.
- `autoSyncResultLabel/Url` (1319–1320) are menu-row state. They are **not** pill state and stay
  with C5.

**Functions:**
- `ensureAutoSyncPill@16045–16090`, `openAutoSyncPillWindow@16097–16108` (KDoc from 16092),
  `stopAutoSyncPillWindow@16110–16114`, `showSyncToast@16124–16164` (KDoc 16116),
  `revealAutoSyncPill@16166–16175`, `hideAutoSyncPillView@16178–16186`,
  `hideAutoSyncCard@16188–16192`.
- ≈ **166 lines**.

**Inbound** (18 sites in 4 declarations):

| function | sites |
|---|---|
| runSubtitleAutoSync@14923 | `showSyncToast` 14929, 14948, 14957, 14965, 14994, 15018, 15030, 15044, 15053, 15064, 15073; `autoSyncPillWindowActive` reads 14962, 14988; `autoSyncPillRing?.arcColor =` write 14966; `hideAutoSyncPillView()` 14989 |
| startAutoSyncLadder@15090 | `openAutoSyncPillWindow()` 15096 |
| maybeRunAutoSyncVerify@15157 | `showSyncToast` 15220 |
| onExternalSubtitleLoaded@15831 | `showSyncToast` 15896 |

**Outbound:**
- `this` ×3 (16047, 16048, 16055); `dp(` ×16; `findViewById` 16085.
- `externalSubtitleHandler` at 16107, 16111, 16132, 16162 and 16189 (borrowed).
- `AutoSyncRingView` and `AutoSyncColors` are already top-level (phase 1).
- `Log.d` (16133).

**Timers:**
- The announce-dismiss (5 s) and card-hide runnables run on the borrowed handler. They are cleared
  only at onDestroy@19195.
- The ring's pulse animator self-cancels in `AutoSyncRingView.onDetachedFromWindow`.

**Tests:** `TvAutoSyncRingCharacterizationTest` covers only the ring and the colours, not the pill.
The open follow-up (plan "P3 → phase 3") adds ring-invalidation assertions; that is independent
of the pill move.

**Shape:** the same as 4a (`activity`, borrowed `handler`, `dp`). Expose `windowActive` and `ring`
for the 3 field reads/writes.

**Activity patches: 18, all inside the C5 engine.** **Recommendation:** move the pill **with C5 in
phase 4**. Its only callers are the engine, so moving the two together makes all 18 edits
intra-controller. Moving it now means patching the engine twice. **Risk: low-medium**, because it
interacts with the ladder/verify runnables on the same handler.

---

### 5. PikPak cold-storage retry (rank 6)

**Owned state:**

| line | name | type / initializer |
|---|---|---|
| 1368 | `isPikPakRetrying` | `Boolean = false` |
| 1369 | `pikPakRetryCount` | `Int = 0` (**write-only** everywhere; never read) |
| 1370 | `pikPakRetryId` | `Int = 0` (**not cleanly ownable**: see below) |
| 1371 | `pikPakRetryHandler` | `val = Handler(Looper.getMainLooper())` |

**Stay** (they would need `::isInitialized` or have outside readers):
- `pikPakReactivationIndicator` (1375, lateinit `View`).
  - Bound at 2670; read at 8685 (isCleanPlaybackState) and 19036 (showBufferingIndicatorDebounced).
  - onDestroy touches it at 19127–19129.
  - The test sets it reflectively (StremioTvStartupWatchdogTest:55).
- `pikPakReactivationText` (1376, lateinit `TextView`), bound at 2671.

**Functions:**
- `playPikPakVideoWithRetry@6652–6705`. This is really media start: subtitle reset,
  `setMediaItem/prepare/play`, `updateTitle`, `restartProgressUpdates`, `fetchStremioSubtitles`.
- `attemptPikPakPlaybackLoop@6707–6801`, `waitForPikPakMetadata@6803–6870` (its local `checkHandler`
  is **never cancelled**; it relies on the retryId guard), `showPikPakRetryOverlay@6873–6889`,
  `hidePikPakRetryOverlay@6891–6898`, `cancelPikPakRetry@6900–6912`.
- Total with the banner 6648–6650 ≈ **265 lines + 5 field + 6 constant lines**.
- The engine-only variant (6707–6912, leaving `playPikPakVideoWithRetry` in the activity) is
  ≈ 206 lines.

**Inbound** (19 patches in 10 declarations; the engine-only variant adds 4 more in
`playPikPakVideoWithRetry`):

| line | enclosing | ref | kind |
|---|---|---|---|
| 4615 | playItem | `cancelPikPakRetry()` | call |
| 4790 | startPlayback | `playPikPakVideoWithRetry(item)` | call |
| 5440 | watchShufflePlayback (15 s posted lambda) | `isPikPakRetrying` | read |
| 17503, 17509, 17511 | schedulePikPakGateReprepare (phase-6 gate) | `pikPakRetryId` | read ×3; 17503 captures, 17509 and 17511 compare at fire time |
| 17755 | onStremioSourceSelected | `cancelPikPakRetry()` | call |
| 18424 | switchToSourcePlaylist | `cancelPikPakRetry()` | call |
| 18578 | switchToStremioSource | `cancelPikPakRetry()` | call |
| 18624, 18625 | switchToStremioSource | `pikPakRetryId++`, `val myRetryId = pikPakRetryId` | write / read |
| 18626, 18627 | switchToStremioSource | `pikPakRetryCount = 0`, `isPikPakRetrying = false` | write ×2 |
| 18628 | switchToStremioSource | `hidePikPakRetryOverlay()` | call |
| 18647 | switchToStremioSource | `attemptPikPakPlaybackLoop(tempItem, 0, myRetryId)` | call |
| 19029 | onPause | `cancelPikPakRetry()` | call |
| 19123 | onDestroy | `cancelPikPakRetry()` | call |
| 19124 | onDestroy | `pikPakRetryHandler.removeCallbacksAndMessages(null)` | call |
| 19667 | playStremioTvPlaybackMap | `cancelPikPakRetry()` | call |

18624–18628 duplicate the reset at 6660–6665. A `beginRetry(): Int` member would replace them but
is not verbatim.

**Outbound** (engine 6707–6912):
- Actions:
  - `cancelPikPakGateReprepare()` 6754, 6830, 6905 and `schedulePikPakGateReprepare(retryId)` 6860
    (phase-6 gate).
  - `failShufflePlayback()` 6766, `failManualSourceCandidate("pikpak-exhausted")` 6767,
    `failStartupCandidate(…)` 6771, `playNext()` 6781, `tryAutoSelectAddonSubtitle()` 6842.
- State: `startupFailoverCursor` 6770, 6880; `isStremioTvMode` 6859; `player` 6718, 6827.
- Views: `startupGateStatus` 6879 (`::isInitialized`), 6882; `pikPakReactivationText` 6884;
  `pikPakReactivationIndicator` 6885–6887, 6893 (`::isInitialized`), 6894–6896.
- Android: `runOnUiThread` 6776, 6874, 6892; `isFinishing` 6775, 6792, 6875, 6893; `isDestroyed`
  6875, 6893; Toast `this` 6777.
- **Do not substitute** `this` at 6819, 6839, 6851 and 6864: there it is the Runnable.
- `playPikPakVideoWithRetry` adds:
  - `resetSubtitleState` 6656, `player` 6668, 6688, `subtitleOverlay` 6674, `payload` 6680.
  - `pendingShufflePlayback` 6689, `subtitleTrackReadiness` 6690, `updateTitle` 6696.
  - `playlistAdapter` and `currentIndex` 6697, `restartProgressUpdates` 6698,
    `fetchStremioSubtitles` 6701.

**Timers:**
- `pikPakRetryHandler`: the exhausted → `playNext` 1500 ms post at 6780.
- The per-call `checkHandler` polls every 500 ms (6864, 6869) and is not tracked.
- Cancel paths:
  - `cancelPikPakRetry` at onPause 19029. This is the **only feature cancelled in onPause**;
    onPause runs it after `super.onPause()` and the ActivityTracker reset.
  - onDestroy 19123–19124, after the iptvBrowseHandler clear and zap token bumps 19114–19120 and before indicator cleanup
    19127 and `bufferingHandler` 19132.
  - Plus 6 navigation sites.

**Tests:** `StremioTvStartupWatchdogTest` (`call` = `declaredMethods.first { name && parameterCount }`):
- `waitForPikPakMetadata`/5 at :176.
- `cancelPikPakRetry`/0 at :192, :221 and :237.
- Field sets `pikPakReactivationIndicator` and `nextOverlay` at :54–55.
- Reads `pikPakGateReprepare` (which stays) at :220 and :224.
- Moving the engine **breaks 4 reflective calls**. Retarget them to the controller instance
  through `read(activity, "<controllerField>")`. Keep the target methods `private` or public on an
  internal class: an `internal` member is name-mangled.
- No Dart anchors. The PikPak assertions in `manual_source_validation_contract_test.dart` target
  the Flutter player, plus the whole-file `startupResolverProvider…`/`startupPikPakTorrent…` strings
  in phase-6 code.

**Proposed shape** (engine-only):
```kotlin
internal class TvPikPakRetryController(private val activity: Activity, private val host: Host) {
    interface Host {
        val player: ExoPlayer?; val isStremioTvMode: Boolean; val startupFailoverCursor: StartupFailoverCursor?
        val startupGateStatusBound: Boolean; val startupGateStatus: TextView
        val indicatorBound: Boolean; val pikPakReactivationIndicator: View; val pikPakReactivationText: TextView
        fun cancelPikPakGateReprepare(); fun schedulePikPakGateReprepare(retryId: Int?)
        fun failShufflePlayback(): Boolean; fun failManualSourceCandidate(reason: String): Boolean
        fun failStartupCandidate(reason: String); fun playNext(); fun tryAutoSelectAddonSubtitle()
    }
}
```
Check the exact signatures and defaulted parameters of `failManualSourceCandidate` (17152),
`failStartupCandidate` (17351) and `playNext` (5228) before fixing the interface.

**Substitutions:** ≈ 35.

**Activity patches: 19 (+4 test retargets). Risk: medium-high.**
- `pikPakRetryId` is a shared token: the phase-6 gate reads it 3× and `switchToStremioSource`
  writes it.
- The engine calls back into the startup/manual/shuffle gates.
- `playPikPakVideoWithRetry` is phase-7 playback start.
- **Recommendation:** extract with the phase-6 source-switch/startup-gate unit, or at least after
  it, so that `pikPakRetryId` and `schedulePikPakGateReprepare` share one owner.

---

### 6. IPTV recording actions (rank 5)

**Owned state** (moves):
- `recordingEngineEnabled` 9244–9250, `val Boolean by lazy { ProfilePreferenceProjection.getBoolean(this, "recording_engine_enabled", true) }`.
  It is read lazily and fixed per launch; the first read happens on whichever path calls first.
- `recordingRegistryListener` 9254–9256, `val () -> Unit`, guarded by `!isDestroyed && !isFinishing`.
- `notificationPermissionRequestCode` 18991, `val = 7403`. It is used only at 9433.

**Stay:**
- `iptvRecordingController` (197, `by lazy { IptvRecordingController(this) }`, the tee). It has 9
  references in IPTV-live code: 477 (performIptvLiveRetune), 2910/2918 (setupPlayer), 12674,
  14142, 14306/14307, 19011/19012 (onResume). Moving it would add 9 patches.
- `iptvRecordButton` (195), which dock/skin code assigns and styles: 4295, 4546, 9114, 9150, 9712,
  9750, 9794.
- `legacyStoragePermissionRequestCode` (18990, `= 7402`), unless it moves with a patch at 18999.

**Functions:**
- Phase-2 movers are excluded: `isSegmentedStreamUrl` 9258–9272, `xtreamTsTwin` 9279–9295,
  `sanitizeRecordingName` 9667–9672, `recordingTimestamp` 9674–9676.
- Moving:
  - `isCurrentIptvSegmented@9274–9277`, `engineRecordableUrl@9297–9310`,
    `isSchedulableStreamUrl@9312–9325`, `engineTaskIdForCurrentChannel@9327–9333`,
    `recordingResourceFor@9335–9338`.
  - `canRecordCurrentIptv@9340–9354`, `updateRecordButtonState@9356–9374`,
    `toggleIptvRecording@9376–9413`, `maybeAskNotificationPermission@9415–9435`.
  - `toggleEngineRecording@9437–9534`, `promptScheduleRecording@9536–9649` (its body has
    tab-indented lines 9622–9645; the checker normalises indentation only),
    `finalizeIptvRecordingIfActive@9651–9665`.
- With the KDoc/banner (9233–9243) ≈ **395 lines**. The largest yield in phase 3.

**Inbound** (21 patches in 13 declarations):

| line | enclosing | ref |
|---|---|---|
| 451, 462 | performIptvLiveRetune | `isCurrentIptvSegmented()` |
| 478, 479 | performIptvLiveRetune | `finalizeIptvRecordingIfActive()`, `updateRecordButtonState()` |
| 2038 | onCreate | `RecordingRegistry.addListener(recordingRegistryListener)`; before the `mode=="iptv"` early return |
| 2911 | setupPlayer (`iptvRecordingController.onAborted` lambda) | `updateRecordButtonState()` |
| 9116 | setupIptvControls (click) | `toggleIptvRecording()` |
| 9706, 9714 | updateIptvControlPresentation | `recordingEngineEnabled`, `updateRecordButtonState()` |
| 9900 | setupIptvOverlay (`onRecordFuture` lambda) | `promptScheduleRecording(entry, program)` |
| 12673 ×2 | isRecordingCurrentIptvChannel | `recordingEngineEnabled`, `engineTaskIdForCurrentChannel()` |
| 14143, 14240 | setIptvMediaItem | `finalizeIptvRecordingIfActive()`, `updateRecordButtonState()` |
| 14316 | retryIptvAsHlsIfUnrecognized | `updateRecordButtonState()` |
| 14338 | beginIptvPlayback | `finalizeIptvRecordingIfActive()` |
| 18926 | onStop | `finalizeIptvRecordingIfActive()`; after `super.onStop()`, before the twin park and `iptvLiveRecovery.cancel` |
| 19001 | onRequestPermissionsResult | `updateRecordButtonState()` |
| 19100 | onDestroy | `RecordingRegistry.removeListener(recordingRegistryListener)` |
| 19107 | onDestroy | `finalizeIptvRecordingIfActive()` |

Keeping `isCurrentIptvSegmented` in the activity (IPTV-live also uses it) saves 2 patches and adds
1 host member.

**Outbound:**
- IPTV state:
  - `currentIptvStreamUrl` at 9275, 9330, 9350, 9403 and 9474.
  - `iptvHlsForcedUrls` at 9276 and 9308.
  - `iptvChannels` and `currentIptvIndex` at 9405 and 9492.
  - `iptvSources` 9337, `iptvSourceId` 9336, `currentIptvHttpHeaders` 9518.
- Recording state: `iptvRecordingController` at 9360, 9381, 9382, 9407, 9655 and 9656;
  `iptvRecordButton` at 9358.
- Request codes: `legacyStoragePermissionRequestCode` at 9461 and 9547;
  `notificationPermissionRequestCode` at 9433.
- Android: **53 × `this`**, all Activity/Context: Toasts, `ActivityCompat.requestPermissions`
  (needs an Activity), `AlertDialog.Builder` (themed Activity), `startService`,
  `ContextCompat.startForegroundService`, ProfilePreferenceProjection, RecordingScheduleStore,
  RecordingAlarmReceiver, DateFormat.
- Also: `getSharedPreferences(…, MODE_PRIVATE)` 9427, `startService` 9442, `isFinishing` 9255 and
  9658, `isDestroyed` 9255.

**Timers/resources:**
- There is no handler. The registry listener's add (onCreate 2038) and remove (onDestroy 19100)
  must keep their positions.
- The tee finalize runs in onStop 18926 and onDestroy 19107. The order in onDestroy is
  removeListener 19100 → cancelSleepTimer 19103 → finalize 19107.
- `AlertDialog` (9602) and the permission dialogs are not dismissed on destroy. That is the
  existing behaviour.
- onResume 19011 runs the tee's `retryPendingPublish`; it stays.

**Tests:** none reflective. No Dart anchors. The profile/source guard tests scan the `recording/`
package, not this file.

**Proposed shape:**
```kotlin
internal class TvIptvRecordingActions(private val activity: AppCompatActivity, private val host: Host) {
    interface Host {
        val currentIptvStreamUrl: String?; val iptvHlsForcedUrls: Set<String>
        val iptvChannels: List<IptvChannelEntry>; val currentIptvIndex: Int
        val iptvSources: List<IptvSourceEntry>; val iptvSourceId: String?
        val currentIptvHttpHeaders: Map<String, String>
        val iptvRecordingController: IptvRecordingController; val iptvRecordButton: AppCompatButton?
        val legacyStoragePermissionRequestCode: Int
    }
}
```
Verify the exact collection types at 863, 864, 883, 888, 992, 1010 and 1016.

**Substitutions:** `this` → `activity` ×53, ≈ 22 `host.` edits, and `activity.` for
`isFinishing`, `isDestroyed`, `startService`, `getSharedPreferences` and `MODE_PRIVATE`
(→ `Context.MODE_PRIVATE`).

**Activity patches: 21. Risk: medium.** Permission flows, the foreground-service start, profile
authorisation (`jobAuthorizationValid`) and lazy-init timing must be preserved. This feature has
the best lines-per-patch ratio after skip.

---

### 7. "Next" overlay (auto-advance toast) (rank 7: do not extract standalone)

**Owned state:**
- `nextOverlay` 156 (lateinit `View`), `nextText` 157 (lateinit `TextView`), `nextSubtext` 158
  (lateinit `TextView`).
- Related: `nextBackdrop` 161, plus `setNextOverlayBackdrop@5911–5925`. Its only caller passes
  `null` (5906), so the image-load branch is dead.

**Functions:**
- `showNextOverlay@8650–8654`, `fadeInNextOverlay@8656–8661`, `hideNextOverlay@8663–8670`.
- With the banner 8649: ≈ **22 lines**.

**Inbound with the views moved: 23 patches.**
- bindViews 2515–2517 (×3).
- playbackListener: 1742 and 1754 (`showNextOverlay`), 1744 and 1756 (`hideNextOverlay`).
- setResolvingState: 5901 (`nextText`), 5902 (`nextSubtext`), 5903 (`fadeIn`), 5905 (`hide`).
- requestStremioTvNext@19732: 19753 and 19777 (`nextText`), 19754 and 19778 (`nextSubtext`),
  19755 (`fadeIn`), 19770, 19787, 19795, 19809 and 19818 (`hide`).
- Reads: isCleanPlaybackState 8684, showBufferingIndicatorDebounced 19036.

**Inbound with the views kept** (host getters): 12 call patches.

**Outbound:** views only.

**Timers:**
- None owned. The 1500 ms auto-advance-then-hide runs on **progressHandler** (1743, 1755, 19787),
  which belongs to the playback core.
- The fade animators are not cancelled.

**Tests:** StremioTvStartupWatchdogTest:54 sets the field `nextOverlay` reflectively, so moving
the field breaks the test.

**Verdict:** the patch/line ratio is about 1:1, and the real owner is the loading/resolving overlay
(`setResolvingState`, `setNextOverlayBackdrop`, the Stremio TV next-channel flow). Fold it into
phase 7 (title/dock identity/loading overlay) or phase 6 (Stremio TV). **Risk: low; value: low.**

---

### Ranking (activity call-site patches, risk)

| rank | feature | lines out | activity patches (decls) | test retargets | risk | notes |
|---|---|---|---|---|---|---|
| 1 | Skip segments | ≈230 | **8** (4) | 0 | med-low | wide read-only host (≈20 members); 3 `::isInitialized` → host getters |
| 2 | Sleep timer | ≈68 | **13** (4) | 0 | low | `sleepStopLatched` stays (not ownable); enum → top-level |
| 3 | Up Next card | ≈118 | **12** (6) (+2 if before skip) | 1 Dart `_between` anchor | med | keep `isCleanPlaybackState` on the host; do it after skip so `upNextVisible` is a host getter |
| 4 | Status pill | ≈58 | **40** (18), or 3 delegating members | 0 | low | needs a ruling: delegators vs. call-site patches |
| 5 | IPTV recording actions | ≈395 | **21** (13) | 0 | med | 53 `this`→`activity`; the tee controller stays |
| 6 | PikPak retry | ≈206–276 | **19** (10) | 4 reflective calls | med-high | `pikPakRetryId` is shared with the phase-6 gate: best done with phase 6 |
| — | Auto-sync pill | ≈166 | 18 (4, all in C5) | 0 | low-med | move with C5 in phase 4 |
| — | Next overlay | ≈22 | 12–23 | 1 reflective field | low | fold into phase 6/7 |

Suggested phase-3 batch order: skip → sleep → Up Next → recording (→ status pill, if delegators
are allowed). The total is ≈ 810–870 lines out for ≈ 54 patches (+40 or +3 for the status pill).
That is well below the plan's ≈2,500 estimate unless PikPak and the auto-sync pill are pulled
forward. The plan's phase-3 line estimate should be re-measured.

**onDestroy ordering to preserve** (current lines):

| line | step |
|---|---|
| 19100 | `RecordingRegistry.removeListener` |
| 19103 | `cancelSleepTimer` |
| 19107 | `finalizeIptvRecordingIfActive` |
| 19123–19124 | `cancelPikPakRetry` + `pikPakRetryHandler` |
| 19127–19130 | `pikPakReactivationIndicator` |
| 19135 | `upNextHandler` |
| 19148 | `subtitleScope.cancel` |
| 19154–19158 | skip generation/job/scope/cache |
| 19161–19163 | progress/controls/seekbar handlers |
| 19173+ | player release |
| 19195 | `externalSubtitleHandler.removeCallbacksAndMessages` (pill runnables) |

Elsewhere:
- onStop: 18926 finalize (tee).
- onPause: 19029 `cancelPikPakRetry`.
- Per-item reset in playItem: 4611 `hideUpNextCard` → 4612 `resetSkipSegmentState` →
  4615 `cancelPikPakRetry`.

## Phase 3 re-measurement and step T (ec365eb80)

The approved phase-2 merge has a 19,017-line activity and 2,671 PSI declarations. The earlier Phase 3 inventory remains historical at dcbd9aafe; the phase-3 manifest now uses ec365eb80 and the following measured declaration starts (including PSI-attached documentation). Status pill remains deferred.

| Feature | Moved subtrees | Original member starts at ec365eb80 |
| --- | ---: | --- |
| sleep | 12 | `class SleepTimerMode` 1170; `property sleepTimerMode` 1178; `property sleepTimerDeadlineElapsedMs` 1179; `property sleepTimerHandler` 1180; `property sleepTimerRunnable` 1181; `property sleepTimerMinuteOptions` 1182; `fun sleepTimerMinutesLeft()` 8025; `fun sleepTimerValueLabel()` 8032; `fun startSleepCountdown(Int)` 8038; `fun armSleepAtEndOfItem()` 8051; `fun cancelSleepTimer(Boolean)` 8057; `fun fireSleepTimer()` 8065 |
| skip | 18 | `class SkipSegmentRequest` 1149; `property skipSegmentScope` 1160; `property skipSegmentFetchJob` 1161; `property skipSegmentFetchGeneration` 1162; `property loadedSkipSegmentKey` 1163; `property loadingSkipSegmentKey` 1164; `property skipSegments` 1165; `property activeSkipSegment` 1166; `property skipFocusOfferedKey` 1167; `property skipSegmentCache` 1168; `fun currentSkipSegmentRequest(Long)` 7825; `fun updateSkipSegmentState(Long,Long)` 7854; `fun ensureSkipSegments(SkipSegmentRequest)` 7889; `fun presentSkipSegment(TvSkipSegment?,String?)` 7947; `fun skipActiveSegment()` 7997; `fun resetSkipSegmentState()` 8096; `property MAX_SKIP_SEGMENT_CACHE_ENTRIES` 19010; `property IMDB_ID_REGEX` 19011 |
| upnext | 17 | `property upNextCard` 163; `property upNextPoster` 165; `property upNextTitle` 166; `property upNextCountdown` 167; `property upNextVisible` 169; `property upNextTargetIndex` 170; `property upNextDismissedForIndex` 171; `property upNextHandler` 172; `fun maybeShowUpNext()` 8379; `property upNextTicker` 8403; `fun showUpNextCard(Int)` 8434; `fun triggerUpNext()` 8461; `fun dismissUpNext()` 8469; `fun hideUpNextCard()` 8474; `property UP_NEXT_THRESHOLD_MS` 19001; `property UP_NEXT_MIN_DURATION_MS` 19002; `property UP_NEXT_TICK_MS` 19003 |
| recording | 15 | `property recordingEngineEnabled` 8746; `property recordingRegistryListener` 8763; `fun isCurrentIptvSegmented()` 8769; `fun engineRecordableUrl(String)` 8774; `fun isSchedulableStreamUrl(String)` 8789; `fun engineTaskIdForCurrentChannel()` 8804; `fun recordingResourceFor(IptvChannelEntry?)` 8812; `fun canRecordCurrentIptv()` 8817; `fun updateRecordButtonState()` 8833; `fun toggleIptvRecording()` 8853; `fun maybeAskNotificationPermission()` 8892; `fun toggleEngineRecording()` 8914; `fun promptScheduleRecording(IptvChannelEntry,IptvEpgProgram)` 9013; `fun finalizeIptvRecordingIfActive()` 9128; `property notificationPermissionRequestCode` 18088 |

Manifest: 62 moved subtrees, 22 patched activity declarations (52 exact context occurrences), six slot-anchored additions, four controller destinations. Every destination span is either a moved subtree or pinned structure. All 22 phase-1/2 destinations are unchanged against ec365eb80; the reviewed-change whitelist is empty.

Step-T verification: 53 dispatcher tests passed (24 phase 1, eight phase 2, 17 phase 3, four bytecode-parser checks); the complete phase-3 extraction fixture passes and compiles in the evidence-only detached original worktree. Every required negative fails for its named reason. An initially omitted `Intent` import in the fixture was corrected before acceptance; production files in this worktree are untouched.

Original self-comparison: 2,671 declarations classified, zero differences. Historical checks: p1@dcbd9aafe classifies 3,477 declarations, zero differences; p2@ec365eb80 classifies 2,839, zero differences. Current earlier-destination check: zero differences.

`dev/tool/check_kotlin_overloads.py` audits all 58 substituted activity `this` sites from original and fixture JVM invocation descriptors, including lazy/lambda classes. All match. In particular the poster uses `Glide.with(FragmentActivity)` before and after. A separately compiled fixture with `Activity` injection selects `Glide.with(Activity)` and is rejected by the audit (not by compilation). No Runnable `this` is substituted.

Evidence: `p3/remeasured-inventory.json`, `p3/original-self-comparison.log`, `p3/checker-self-tests-final.log`, `p3/historical-p1.log`, `p3/historical-p2.log`, `p3/earlier-destinations.log`, `p3/fixture-compile.log`, `p3/overload-audit.json`, `p3/overload-negative-compile.log`, `p3/overload-negative.log`, `p3/bytecode/`. Shared offline PSI cache remains under the previously approved `p1/psi`.
