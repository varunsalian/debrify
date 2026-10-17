# Phase 15 frozen IPTV Hosts

Prepared against `1d7699d2e` under the Phase 15 design review resolution;
re-derived unchanged on accepted P14 `be4cd78aa`. The complete partition
is FINAL; all earlier destinations remain subject to history protection.

| Destination | Formatted physical lines |
| --- | ---: |
| `vp_iptv_zap_ring.dart` | 347 |
| `vp_iptv_zap_ladder.dart` | 283 |
| `vp_iptv_guide_catchup.dart` | 408 |
| `vp_iptv_channel_switch.dart` | 433 |
| `vp_iptv_live_sources.dart` | 245 |
| `vp_iptv_watch_memory.dart` | 207 |
| `vp_iptv_zap_banner.dart` | 162 |

## VpIptvZapRingHost

21 names; 26 declarations.

```dart
abstract interface class VpIptvZapRingHost {
  void anchorIptvGuideCategory(IptvChannel channel, {Object? categories});
  void clearIptvZapBoundaryCache();
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  set currentIptvIndex(int v);
  List<IptvChannel>? get effectiveIptvChannels;
  set iptvChannelsOverride(List<IptvChannel>? v);
  int get iptvGuideContextGeneration;
  IptvGuideContext? get iptvGuideContextOverride;
  int get iptvSwitchTicket;
  set iptvZapCategories(List<String> v);
  String? get iptvZapCategory;
  set iptvZapCategory(String? v);
  set iptvZapCategoryTotal(int v);
  bool get iptvZapPagingActive;
  set iptvZapPagingActive(bool v);
  List<int> get iptvZapPendingInputs;
  bool get iptvZapRequestInFlight;
  set iptvZapRequestInFlight(bool v);
  int get iptvZapWindowOffset;
  set iptvZapWindowOffset(int v);
  int get iptvZapPageSize;
  bool get mounted;
  void setState(VoidCallback fn);
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  get iptvBrowseProvider;
  String? get iptvSourceId;
}
```

## VpIptvZapLadderHost

18 names; 18 declarations.

```dart
abstract interface class VpIptvZapLadderHost {
  void applyIptvGuideCategory(String? category, List<String>? categories);
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  List<IptvChannel>? get effectiveIptvChannels;
  void ensureIptvZapPagingArmed();
  void installIptvZapWindow(
    VpIptvZapPage page, {
    required bool preservePlayingChannel,
  });
  List<String> get iptvZapCategories;
  String? get iptvZapCategory;
  int get iptvZapCategoryTotal;
  bool get iptvZapPagingActive;
  List<int> get iptvZapPendingInputs;
  bool get iptvZapRequestInFlight;
  int get iptvZapWindowOffset;
  int get iptvZapPageSize;
  void mergeIptvZapPage(VpIptvZapPage page);
  Future<VpIptvZapPage?> requestIptvZapPage({
    required String? category,
    required int offset,
    bool fromEnd = false,
  });
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false});
  bool get mounted;
}
```

## VpIptvGuideCatchupHost

32 names; 37 declarations.

```dart
abstract interface class VpIptvGuideCatchupHost {
  ValueNotifier<bool> get controlsVisible;
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  Duration get duration;
  List<IptvChannel>? get effectiveIptvChannels;
  void hideIptvZapBanner({bool immediate = false});
  set iptvChannelsOverride(List<IptvChannel>? v);
  IptvTuneDiagnostics get iptvDiag;
  int get iptvGuideContextGeneration;
  set iptvGuideContextGeneration(int v);
  IptvGuideContext? get iptvGuideContextOverride;
  set iptvGuideContextOverride(IptvGuideContext? v);
  IptvLiveRecovery get iptvLiveRecovery;
  bool iptvRecoveryEligible();
  bool get iptvStartOverActive;
  set iptvStartOverActive(bool v);
  bool get iptvStartOverLoading;
  set iptvStartOverLoading(bool v);
  bool get iptvStartOverTimelineRequested;
  set iptvStartOverTimelineRequested(bool v);
  int get iptvSwitchTicket;
  EpgNowNext? get iptvZapEpg;
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  });
  Future<void> reanchorIptvRingToCategory(
    IptvChannel channel, {
    required int switchTicket,
  });
  void resetIptvZapPaging();
  void scheduleAutoHide();
  set showIptvChannelSheet(bool v);
  Future<void> stopRecording({bool userInitiated = true});
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false});
  FocusNode get tvProgressFocus;
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  String? get iptvSourceId;
  List<String>? get iptvCategories;
  String? get iptvContentType;
  String? get iptvSourceName;
}
```

## VpIptvChannelSwitchHost

54 names; 61 declarations.

```dart
abstract interface class VpIptvChannelSwitchHost {
  bool get activeMediaUserPaused;
  void anchorIptvGuideCategory(IptvChannel channel, {Object? categories});
  Future<void> applyIptvAudioPreference(int ticket);
  void cancelPendingIptvCatchup({bool hideFeedback = true});
  void clearBufferingIndicator();
  set currentChannelName(String? v);
  set currentChannelNumber(int? v);
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  set currentIptvIndex(int v);
  int get currentSourceIndex;
  set currentSourceIndex(int v);
  List<IptvChannel>? get effectiveIptvChannels;
  bool get engineFlagOn;
  void hideIptvChannelSheet();
  void hideIptvZapBanner({bool immediate = false});
  void hideSourceSheet();
  String? get iptvChannelKey;
  IptvTuneDiagnostics get iptvDiag;
  set iptvErrorsMuted(bool v);
  IptvLiveRecovery get iptvLiveRecovery;
  ValueNotifier<String?> get iptvReconnectText;
  bool get iptvStartOverActive;
  set iptvStartOverActive(bool v);
  bool get iptvStartOverLoading;
  set iptvStartOverLoading(bool v);
  set iptvStartOverTimelineRequested(bool v);
  int get iptvSwitchTicket;
  set iptvSwitchTicket(int v);
  bool get iptvZapPagingActive;
  bool get isIptvSeriesContext;
  set isTransitioning(bool v);
  set lastIptvErrorShown(DateTime? v);
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  });
  bool get pausedByLifecycle;
  mk.Player get player;
  void prepareIptvBannerData(IptvChannel channel);
  set rainbowActive(bool v);
  AnimationController get rainbowController;
  void raiseIptvZapBanner();
  Future<void> recordIptvWatchForChannel(IptvChannel channel);
  Future<void> refreshEngineRecordingState();
  ResumeWriteGuard get resumeWriteGuard;
  bool get screenDisposed;
  void setIptvSources(
    String? channelKey,
    List<StremioIptvCandidate>? candidates, {
    int currentIndex = 0,
  });
  bool get sleepStopLatched;
  void startTransitionOverlay();
  Future<void> stopRecording({bool userInitiated = true});
  set transitionPhase(int v);
  set transitionPhase2Started(DateTime? v);
  Timer? get transitionPhaseTimer;
  set transitionRunning(bool v);
  Timer? get transitionStopTimer;
  set transitionStopTimer(Timer? v);
  Future<bool> tryOpenLiveStream(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
  });
  void tvAbandonScrub();
  int get tvScrubGeneration;
  set tvScrubGeneration(int v);
  bool get mounted;
  void setState(VoidCallback fn);
  SleepTimerMode get sleepTimerMode;
}
```

## VpIptvLiveSourcesHost

23 names; 28 declarations.

```dart
abstract interface class VpIptvLiveSourcesHost {
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  set currentSourceIndex(int v);
  List<IptvChannel>? get effectiveIptvChannels;
  String? get iptvChannelKey;
  set iptvChannelKey(String? v);
  IptvTuneDiagnostics get iptvDiag;
  bool get iptvErrorsMuted;
  IptvLiveRecovery get iptvLiveRecovery;
  bool iptvRecoveryEligible();
  bool get iptvStartOverActive;
  set iptvStartOverActive(bool v);
  set iptvStartOverTimelineRequested(bool v);
  DateTime? get lastIptvErrorShown;
  set lastIptvErrorShown(DateTime? v);
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  });
  mk.Player get player;
  Future<String?> Function(Torrent)? get resolveStremioSourceOverride;
  set resolveStremioSourceOverride(Future<String?> Function(Torrent)? v);
  Future<void> stopRecording({bool userInitiated = true});
  List<Torrent>? get stremioSourcesOverride;
  set stremioSourcesOverride(List<Torrent>? v);
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false});
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  int? get iptvStartIndex;
  String get videoUrl;
}
```

## VpIptvWatchMemoryHost

8 names; 8 declarations.

```dart
abstract interface class VpIptvWatchMemoryHost {
  IptvChannel? get currentIptvChannel;
  IptvGuideContext? get iptvGuideContextOverride;
  int get iptvSwitchTicket;
  bool get isIptvSeriesContext;
  bool get isPlaying;
  mk.Player get player;
  bool get mounted;
  String? get iptvSourceId;
}
```

## VpIptvZapBannerHost

13 names; 18 declarations.

```dart
abstract interface class VpIptvZapBannerHost {
  ValueNotifier<bool> get controlsVisible;
  bool get iptvZapBannerOwnsIdentity;
  IptvChannel? get iptvZapChannel;
  set iptvZapChannel(IptvChannel? v);
  set iptvZapClock(DateTime v);
  EpgNowNext? get iptvZapEpg;
  set iptvZapEpg(EpgNowNext? v);
  bool get iptvZapEpgLoading;
  set iptvZapEpgLoading(bool v);
  bool get iptvZapFloatingMounted;
  set iptvZapFloatingMounted(bool v);
  bool get showChannelGuide;
  bool get showIptvChannelSheet;
  bool get showIptvZapBanner;
  set showIptvZapBanner(bool v);
  bool get showSourceSheet;
  bool get mounted;
  void setState(VoidCallback fn);
}
```

The eight watch-memory names are exactly the approved set. Only the switch
Host can write `iptvSwitchTicket`; the page-size constant and all fields shared
between collaborators stay in the State. Constructors store their Host only.
No sibling collaborator object is exposed. Cross actions use synchronous
expression forwarders, retaining each action’s synchronous prefix.

The four facade adapter classes to regenerate on the accepted P14 base are
`_VpPipLifecycleHostAdapter`, `_VpPlayerMenuUiHostAdapter`,
`_VpPlayerMenuHostAdapter`, and `_VpTrackPreferencesHostAdapter`. The latter
changes only its audio action; its ticket getter remains State-owned.

The preparation scan contains 68 occurrences: the plan’s 62 core retained
sites (60 facade sites plus two lazy-initializer references), four menu callers
that P13 will replace with facade adapter routing, and two existing P8/P11
adapter forwarders. The scanner retains all 68; no named reference is dropped.
Recompute the ledger, all adapters, imports/orders, analyzer probes and witnesses
after P13/P14; no provisional count substitutes for that check.

Final rebase materialization (accepted P14 `be4cd78aa`) preserves every Host
signature and its declaration order. All seven formatted sizes remain unchanged.
The final retained scan has 67 occurrences: 62 core sites plus five actions in
four regenerated P8/P11/P13 adapters; P13's two menu audio calls now share one
facade adapter. The P11 ticket getter and all P14 adapters remain unchanged.
