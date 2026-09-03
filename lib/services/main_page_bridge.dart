import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../models/advanced_search_selection.dart';
import '../models/rd_torrent.dart';
import '../models/torbox_torrent.dart';

typedef SyncedProfileOutcomeApply = Future<void> Function();
typedef SyncedProfileRetirementHandoff =
    Future<bool> Function(
      String profileId, {
      required bool delete,
      required SyncedProfileOutcomeApply applyOutcome,
    });

/// Stable page identities for [MainPageBridge.switchTab], deep links and the
/// nav — indices into main.dart's `_pages`/`_titles`, NEVER visible-nav
/// positions (per-profile and per-config filtering hides entries without
/// renumbering; see `_applyProfilePolicy`). Every numeric caller names its
/// target through this table — the nav-index audit's close-out.
///
/// [legacyTorrentSearch] is the deprecated index-0 slot some cloud screens
/// still target on their "return to search" path; named rather than silently
/// retargeted so the legacy behavior stays visible and greppable.
abstract final class MainTab {
  static const int legacyTorrentSearch = 0;
  static const int playlist = 1;
  static const int downloads = 2;
  static const int debrifyTv = 3;
  static const int realDebrid = 4;
  static const int torbox = 5;
  static const int pikPak = 6;
  static const int addons = 7;
  static const int settings = 8;
  static const int stremioTv = 9;
  static const int webDav = 10;
  static const int premiumize = 11;
  static const int allDebrid = 12;
  static const int iptv = 13;
  static const int youtube = 14;
  static const int home = 15;
  static const int cloud = 16;
  static const int search = 17;
  static const int discover = 18;
  static const int calendar = 19;
}

class MainPageBridge {
  static void Function(int index)? switchTab;

  /// Stable page identities for [switchTab], deep links and the nav — these
  /// are indices into main.dart's `_pages`/`_titles`, NEVER visible-nav
  /// positions (per-profile and per-config filtering hides entries without
  /// renumbering; see `_applyProfilePolicy`). Every numeric caller names its
  /// target through this table — the nav-index audit's close-out.
  ///
  /// [legacyTorrentSearch] is the deprecated index-0 slot some cloud screens
  /// still target on their "return to search" path; kept named rather than
  /// silently retargeted so the legacy behavior stays visible and greppable.

  static VoidCallback? showProfilePicker;
  static ValueChanged<String>? switchProfile;

  /// Gate-owned handoff for a circle value which makes the active profile
  /// ineligible. Returns true only after the deferred delete/disable lands.
  static SyncedProfileRetirementHandoff? retireProfileFromSync;

  /// Re-reads the ACTIVE profile's policy into MainPage's tab gating and the
  /// ProfilePolicyGuard sync mirror. Editing screens call this after saving
  /// the signed-in profile — that path never crosses the gate, which is what
  /// refreshes the mirrors everywhere else.
  static VoidCallback? reloadProfilePolicy;

  /// Drops one-shot data owned by the outgoing profile. Callback registrations
  /// are lifecycle-owned by widgets and are deliberately left alone; only
  /// content-bearing handoffs are invalidated here.
  static void clearProfileSessionState() {
    pendingCatalogDetailOpen = null;
    pendingMdblistListOpen = null;
    _pendingPostSetupSnackBarMessage = null;
    _debrifyTvChannelToAutoPlay = null;
    _stremioTvChannelToAutoPlay = null;
    cancelIptvStartupChannel();
    _continueWatchingItemToAutoPlay = null;
    _advancedSearchSelectionToAutoPlay = null;
  }

  /// Fired by Settings when the phone-nav style or bar slots change, so the
  /// main shell swaps chrome without a restart.
  static VoidCallback? navPrefsChanged;

  /// Last loaded phone-nav style, for synchronous layout reads (e.g. the
  /// keyword bar's clearance for the floating button, which the classic bar
  /// doesn't have). 'classic' | 'floating'.
  static String phoneNavStyleCached = 'classic';

  /// Fired by the TV Home Layout picker after writing `tv_home_style`, so the
  /// live Home board re-reads the pref and rebuilds without a restart. Set by
  /// the HOME SearchScreen instance only (not the Search tab's).
  static VoidCallback? tvHomeStyleChanged;

  /// Fired after the TV Hero Artwork Quality picker updates the process-scoped
  /// decode policy. The live Home board rebuilds its image widgets so the new
  /// ResizeImage cache key takes effect without an app restart.
  static VoidCallback? tvHeroArtworkQualityChanged;

  /// Fired by the Discover Layout picker after writing `discover_layout`, so
  /// the live Discover tab re-reads the pref and swaps between the grid and
  /// the stage without a restart. Set by the DISCOVER SearchScreen instance
  /// only (the Home board and the Search tab never render that layout).
  static VoidCallback? discoverLayoutChanged;

  /// Fired after the Discover poster-detail toggles change. The live Discover
  /// tab rebuilds its shared card scope, so every source updates immediately.
  static VoidCallback? discoverCardSettingsChanged;

  /// Fired by the TV Sidebar Style picker after writing `tv_sidebar_style`,
  /// so the app shell re-reads the pref and reskins the rail live. Set by
  /// main.dart.
  static VoidCallback? tvSidebarStyleChanged;

  /// Same contract for the desktop/tablet sidebar picker
  /// (`desktop_sidebar_style`): the shell re-reads the pref and swaps the
  /// fixed rail for the pill (or back) live. Set by main.dart.
  static VoidCallback? desktopSidebarStyleChanged;

  /// Fired after the active profile's shared TV/desktop sidebar order or
  /// labels change. MainPage re-reads the atomic configuration and rebuilds
  /// both sidebar variants without disturbing routing or visibility policy.
  static VoidCallback? sidebarConfigurationChanged;

  /// Reloads the mounted Playlist tab after recurring sync changes its
  /// profile-backed items or favourites.
  static final Set<Future<void> Function()> _playlistChangeListeners = {};

  static void addPlaylistChangeListener(Future<void> Function() listener) {
    _playlistChangeListeners.add(listener);
  }

  static void removePlaylistChangeListener(Future<void> Function() listener) {
    _playlistChangeListeners.remove(listener);
  }

  static Future<void> notifyPlaylistChanged() async {
    final listeners = List<Future<void> Function()>.from(
      _playlistChangeListeners,
    );
    await Future.wait<void>(
      listeners.map((listener) async {
        try {
          await listener();
        } catch (error) {
          // A stale or failed mounted consumer must not prevent the other
          // playlist surfaces from observing the committed sync revision.
          debugPrint(
            'MainPageBridge: playlist refresh listener failed '
            '(${error.runtimeType})',
          );
        }
      }),
    );
  }

  static void Function(RDTorrent torrent)? openDebridOptions;
  static void Function(TorboxTorrent torrent)? openTorboxFolder;
  static void Function(String fileId, String folderName)? openPikPakFolder;
  static void Function()? openPremiumizeFolder;
  static void Function()? openAllDebridFolder;

  /// Open a specific cloud provider from the consolidated "Cloud" tab. Pushes
  /// the provider's screen (like [openDebridOptions] et al.) so "view in
  /// provider" and post-add flows land on the right provider even though the
  /// six providers no longer have their own nav tabs. [providerKey] is one of:
  /// 'realdebrid' | 'torbox' | 'pikpak' | 'premiumize' | 'alldebrid' | 'webdav'.
  /// Shows the same missing-key / hidden-tab snackbar as [switchTab] did when
  /// the provider isn't available. Set by main.dart.
  static void Function(String providerKey)? openCloudProvider;

  /// Flag to track if user came from torrent search "Open in xxx" flow.
  /// When true, back navigation should return to torrent search instead of folder navigation.
  static bool returnToTorrentSearchOnBack = false;
  static Future<void> Function(
    Map<String, dynamic> result,
    String torrentName,
    String apiKey,
  )?
  handleRealDebridResult;
  static Future<void> Function(TorboxTorrent torrent)? handleTorboxResult;
  static Future<void> Function(String fileId, String fileName)?
  handlePikPakResult;
  static VoidCallback? hideAutoLaunchOverlay;

  /// Asks the AllDebrid screen to switch to its "Web Downloads" view and
  /// refresh, used after a shared web link is saved. Set by the AllDebrid
  /// screen when it's mounted; if it isn't (the common case — the tab is built
  /// fresh on switch), [notifyAllDebridFocusWebDownloads] stores a pending flag
  /// that the screen consumes in initState.
  static Future<void> Function()? focusAllDebridWebDownloads;
  static bool _allDebridFocusWebDownloadsPending = false;

  static void notifyAllDebridFocusWebDownloads() {
    final handler = focusAllDebridWebDownloads;
    if (handler != null) {
      _allDebridFocusWebDownloadsPending = false;
      unawaited(handler());
      return;
    }
    _allDebridFocusWebDownloadsPending = true;
  }

  static bool getAndClearAllDebridFocusWebDownloads() {
    final pending = _allDebridFocusWebDownloadsPending;
    _allDebridFocusWebDownloadsPending = false;
    return pending;
  }

  /// Fired only when playback was handed off to a *separate external
  /// activity* (Android TV native player, DeoVR, or an external player app)
  /// — i.e. control returns to Flutter immediately while that activity is
  /// still launching. NOT fired for the in-app player route. Lets a screen
  /// keep a launch mask up until app resume so the bare UI doesn't flash
  /// during the external activity's launch transition.
  static VoidCallback? onExternalPlayerLaunched;

  /// Multicast companions to [onExternalPlayerLaunched] (which is a single
  /// slot owned by the torrent search screen). Any number of listeners may
  /// register — e.g. the detail page's ambient trailer stops itself when
  /// playback moves to an external player, since no Flutter route is pushed
  /// in that case and window focus is an unreliable proxy on desktop.
  static final Set<VoidCallback> _externalPlayerLaunchListeners = {};

  static void addExternalPlayerLaunchListener(VoidCallback listener) {
    _externalPlayerLaunchListeners.add(listener);
  }

  static void removeExternalPlayerLaunchListener(VoidCallback listener) {
    _externalPlayerLaunchListeners.remove(listener);
  }

  static Future<void> Function(String channelId)? watchDebrifyTvChannel;
  static Future<void> Function(String channelId)? watchStremioTvChannel;
  static Future<void> Function(Map<String, dynamic> item)?
  watchContinueWatchingItem;
  static Future<void> Function(AdvancedSearchSelection selection)?
  watchAdvancedSearchSelection;

  /// A one-shot request from another tab (e.g. the Trakt Calendar, which is its
  /// own tab and can't reach the Home board's state directly) to open a catalog
  /// detail page on the Home board. The requester fills this, switches to Home
  /// via [switchTab], and the Home SearchScreen consumes it on mount. Keys:
  /// imdbId, type ('series'|'movie'), title, year (int?), poster, season (int?),
  /// episode (int?), originTab (int? — tab to return to when the detail closes).
  static Map<String, dynamic>? pendingCatalogDetailOpen;

  /// Live counterpart to [pendingCatalogDetailOpen], owned by the mounted Home
  /// board. Top Shelf can open the app while Home is already active, in which
  /// case switching to tab 15 would not remount it and consume the pending map.
  static Future<void> Function(Map<String, dynamic> data)?
  _catalogDetailOpenHandler;

  static void registerCatalogDetailOpenHandler(
    Future<void> Function(Map<String, dynamic> data) handler,
  ) {
    _catalogDetailOpenHandler = handler;
  }

  static void unregisterCatalogDetailOpenHandler(
    Future<void> Function(Map<String, dynamic> data) handler,
  ) {
    if (_catalogDetailOpenHandler == handler) {
      _catalogDetailOpenHandler = null;
    }
  }

  /// Routes a detail request to the live Home board when it is visible, or
  /// stores a one-shot handoff and switches Home in when another tab is active.
  static void requestCatalogDetailOpen(Map<String, dynamic> data) {
    final copied = Map<String, dynamic>.from(data);
    final handler = _catalogDetailOpenHandler;
    if (_activeTvTabIndex == MainTab.home && handler != null) {
      pendingCatalogDetailOpen = null;
      unawaited(handler(copied));
      return;
    }
    pendingCatalogDetailOpen = copied;
    switchTab?.call(MainTab.home);
  }

  /// A one-shot request from the Search tab's Lists mode to open a specific
  /// MDBList list on the Discover tab. The requester fills this and switches to
  /// Discover via [switchTab]; the Discover SearchScreen consumes it on mount.
  /// Keys mirror MdblistListChoice: id (int), name, ownerName (String?),
  /// itemCount (int), liked (bool), likes (int).
  static Map<String, dynamic>? pendingMdblistListOpen;

  // ==========================================================================
  // Back Navigation Handling
  // ==========================================================================
  // Two types of handlers:
  // 1. Tab handlers - for tab screens (RealDebrid, TorBox, PikPak). Only one active at a time.
  // 2. Pushed route stack - for screens pushed on top (e.g., playlist content view).
  // ==========================================================================

  /// Tab handlers registered by key (e.g., "realdebrid", "torbox", "pikpak")
  static final Map<String, bool Function()> _tabHandlers = {};

  /// Currently active tab key
  static String? _activeTabKey;

  /// Stack of handlers for pushed routes (on top of tab screens)
  static final List<bool Function()> _pushedRouteStack = [];

  /// Register a tab's back handler. Call in initState of tab screens.
  static void registerTabBackHandler(String key, bool Function() handler) {
    _tabHandlers[key] = handler;
  }

  /// Unregister a tab's back handler. Call in dispose of tab screens. Pass the
  /// same [handler] that was registered so a screen tearing down mid-transition
  /// only removes its own entry — during the tab AnimatedSwitcher the new
  /// instance may have already re-registered under the same key, and a blind
  /// key-only remove would clobber the newer handler. Key-only remove (omit
  /// [handler]) is kept for callers that don't hold onto their closure.
  static void unregisterTabBackHandler(String key, [bool Function()? handler]) {
    if (handler != null && _tabHandlers[key] != handler) return;
    _tabHandlers.remove(key);
  }

  /// Set the currently active tab. Call from main.dart when tab changes.
  static void setActiveTab(String? key) {
    _activeTabKey = key;
  }

  /// Push a handler for a pushed route. Call in initState of pushed screens.
  static void pushRouteBackHandler(bool Function() handler) {
    _pushedRouteStack.add(handler);
  }

  /// Pop a handler for a pushed route. Call in dispose of pushed screens.
  static void popRouteBackHandler(bool Function() handler) {
    if (_pushedRouteStack.isNotEmpty && _pushedRouteStack.last == handler) {
      _pushedRouteStack.removeLast();
    }
  }

  /// Handle back navigation. Checks pushed routes first, then active tab.
  /// Returns true if handled, false otherwise.
  static bool handleBackNavigation() {
    // First, check pushed route handlers (most recent first)
    if (_pushedRouteStack.isNotEmpty) {
      if (_pushedRouteStack.last()) {
        return true;
      }
    }

    // Then, check the active tab's handler
    if (_activeTabKey != null && _tabHandlers.containsKey(_activeTabKey)) {
      return _tabHandlers[_activeTabKey]!();
    }

    return false;
  }

  static final List<VoidCallback> _integrationListeners = [];

  static void addIntegrationListener(VoidCallback listener) {
    if (_integrationListeners.contains(listener)) return;
    _integrationListeners.add(listener);
  }

  static void removeIntegrationListener(VoidCallback listener) {
    _integrationListeners.remove(listener);
  }

  static void notifyIntegrationChanged() {
    for (final listener in List<VoidCallback>.from(_integrationListeners)) {
      listener();
    }
  }

  static final List<VoidCallback> _homeSettingsListeners = [];

  static void addHomeSettingsListener(VoidCallback listener) {
    if (_homeSettingsListeners.contains(listener)) return;
    _homeSettingsListeners.add(listener);
  }

  static void removeHomeSettingsListener(VoidCallback listener) {
    _homeSettingsListeners.remove(listener);
  }

  static void notifyHomeSettingsChanged() {
    for (final listener in List<VoidCallback>.from(_homeSettingsListeners)) {
      listener();
    }
  }

  static String? _pendingPostSetupSnackBarMessage;

  static void queuePostSetupSnackBar(String message) {
    _pendingPostSetupSnackBarMessage = message;
  }

  static String? takePostSetupSnackBar() {
    final message = _pendingPostSetupSnackBarMessage;
    _pendingPostSetupSnackBarMessage = null;
    return message;
  }

  static final Set<VoidCallback> _playerLaunchListeners = {};
  static final Set<VoidCallback> _contentPlaybackStopListeners = {};
  static bool _contentPlaybackActive = false;

  /// Notified right before the real content player launches (movie/series),
  /// on every path — in-app route, native TV activity, or external app.
  static void addPlayerLaunchListener(VoidCallback listener) {
    _playerLaunchListeners.add(listener);
  }

  static void removePlayerLaunchListener(VoidCallback listener) {
    _playerLaunchListeners.remove(listener);
  }

  /// Completion signal shared by in-app and external content players.
  static void addContentPlaybackStopListener(VoidCallback listener) {
    _contentPlaybackStopListeners.add(listener);
  }

  static void removeContentPlaybackStopListener(VoidCallback listener) {
    _contentPlaybackStopListeners.remove(listener);
  }

  static void notifyContentPlaybackStopped() {
    if (!_contentPlaybackActive) return;
    _contentPlaybackActive = false;
    for (final listener in List.of(_contentPlaybackStopListeners)) {
      listener();
    }
  }

  /// Human handoff moments inside playback — pause, a settled seek, an
  /// explicit checkpoint save. Listeners (WebDAV sync) may flush immediately.
  static final Set<VoidCallback> _playbackCheckpointListeners = {};

  static void addPlaybackCheckpointListener(VoidCallback listener) {
    _playbackCheckpointListeners.add(listener);
  }

  static void removePlaybackCheckpointListener(VoidCallback listener) {
    _playbackCheckpointListeners.remove(listener);
  }

  static void notifyPlaybackCheckpoint() {
    for (final listener in List.of(_playbackCheckpointListeners)) {
      listener();
    }
  }

  /// [isTrailer] true for a trailer launch: it still hides the auto-launch
  /// overlay, but does NOT fire the content-launch listeners — watching a
  /// trailer must not suppress the ambient trailer backdrop.
  static void notifyPlayerLaunching({bool isTrailer = false}) {
    hideAutoLaunchOverlay?.call();
    if (isTrailer) return;
    _contentPlaybackActive = true;
    // Copy so a listener removing itself mid-iteration can't break the loop.
    for (final listener in List.of(_playerLaunchListeners)) {
      listener();
    }
  }

  /// Call right before returning from an external-activity playback launch
  /// (see [onExternalPlayerLaunched]).
  static void notifyExternalPlayerLaunched() {
    onExternalPlayerLaunched?.call();
    // Copy so a listener removing itself mid-iteration can't break the loop.
    for (final listener in List.of(_externalPlayerLaunchListeners)) {
      listener();
    }
  }

  static final Set<VoidCallback> _playbackReturnListeners = {};

  /// The missing counterpart to [notifyExternalPlayerLaunched]: fired when the
  /// app comes back to the foreground *after* content playback ran in a
  /// SEPARATE ACTIVITY (Android TV native player, DeoVR, external app).
  ///
  /// Those launches never push a Flutter route, so the `RouteAware.didPopNext`
  /// hook that every detail page / board / See-All grid uses to re-read watch
  /// progress simply never fires for them — the resume label, episode ticks and
  /// Continue Watching rows would sit stale until the screen was rebuilt. This
  /// is the signal that says "playback is over, re-read your state".
  ///
  /// Deliberately NOT fired for the in-app player (its route pop already drives
  /// didPopNext — firing here too would double every refresh) and not for
  /// trailers (they change no watch state).
  ///
  /// Listeners should gate on their route being current: the top screen owns
  /// the refresh, and anything buried under it re-reads on its own didPopNext
  /// when the covering route pops.
  static void addPlaybackReturnListener(VoidCallback listener) {
    _playbackReturnListeners.add(listener);
  }

  static void removePlaybackReturnListener(VoidCallback listener) {
    _playbackReturnListeners.remove(listener);
  }

  static void notifyPlaybackReturned() {
    // Copy so a listener removing itself mid-iteration can't break the loop.
    for (final listener in List.of(_playbackReturnListeners)) {
      listener();
    }
    notifyContentPlaybackStopped();
  }

  /// Re-read playback-derived UI after a committed background materialization
  /// without claiming that an active mobile playback session stopped.
  static void notifyPlaybackDataChanged() {
    for (final listener in List.of(_playbackReturnListeners)) {
      listener();
    }
  }

  // Debrify TV has one mounted library surface. Keep this hook deliberately
  // narrower than the generic playback-return listeners: a remote channel or
  // pool apply only asks that screen to invalidate its private DB mirrors.
  static VoidCallback? _debrifyTvLibraryListener;

  static void registerDebrifyTvLibraryListener(VoidCallback listener) {
    _debrifyTvLibraryListener = listener;
  }

  static void unregisterDebrifyTvLibraryListener(VoidCallback listener) {
    if (_debrifyTvLibraryListener == listener) {
      _debrifyTvLibraryListener = null;
    }
  }

  static void notifyDebrifyTvLibraryChanged() {
    _debrifyTvLibraryListener?.call();
  }

  static void notifyAutoLaunchFailed([String? reason]) {
    debugPrint('MainPageBridge: Auto-launch failed: $reason');
    hideAutoLaunchOverlay?.call();
    notifyContentPlaybackStopped();
  }

  // Store a Debrify TV channel ID that should be auto-played when DebrifyTVScreen initializes
  static String? _debrifyTvChannelToAutoPlay;

  static void notifyDebrifyTvChannelToAutoPlay(String channelId) {
    _debrifyTvChannelToAutoPlay = channelId;
  }

  static String? getAndClearDebrifyTvChannelToAutoPlay() {
    final channelId = _debrifyTvChannelToAutoPlay;
    _debrifyTvChannelToAutoPlay = null;
    return channelId;
  }

  // Store a Stremio TV channel ID that should be auto-played when StremioTvScreen initializes
  static String? _stremioTvChannelToAutoPlay;

  static void notifyStremioTvChannelToAutoPlay(String channelId) {
    _stremioTvChannelToAutoPlay = channelId;
  }

  static String? getAndClearStremioTvChannelToAutoPlay() {
    final channelId = _stremioTvChannelToAutoPlay;
    _stremioTvChannelToAutoPlay = null;
    return channelId;
  }

  // ==========================================================================
  // IPTV startup channel
  //
  // main() resolves the channel before runApp and stashes it here; the IPTV
  // page consumes it once, after its catalog is loaded.
  //
  // Cancellation is TWO mechanisms on purpose. The callback is the fast path,
  // but the overlay can be on screen before IptvResultsView has registered one
  // — so BACK would hit a null callback while the payload stayed consumable,
  // and the launch would proceed moments later. The epoch is the durable truth:
  // the payload carries the epoch it was dispatched under, consumption requires
  // it to still match, and cancelling increments. That also stops a stale
  // cancellation from killing an unrelated later attempt.
  // ==========================================================================

  static Map<String, dynamic>? _iptvStartupChannel;
  static int _iptvStartupEpoch = 0;
  static int _iptvStartupPayloadEpoch = -1;

  /// Registered by IptvResultsView while it owns a startup attempt, so BACK /
  /// timeout can abort work already in flight.
  static VoidCallback? cancelIptvStartup;

  /// Called from main() before the first frame.
  static void setIptvStartupChannel(Map<String, dynamic> channel) {
    _iptvStartupChannel = channel;
    _iptvStartupPayloadEpoch = _iptvStartupEpoch;
  }

  /// True while a startup channel is pending and not cancelled — drives the
  /// overlay and the splash hand-off.
  static bool get hasPendingIptvStartup =>
      _iptvStartupChannel != null &&
      _iptvStartupPayloadEpoch == _iptvStartupEpoch;

  /// The pending channel, consumed once. Returns null if it was cancelled
  /// before the page got to it (epoch moved on).
  static Map<String, dynamic>? consumeIptvStartupChannel() {
    if (!hasPendingIptvStartup) {
      _iptvStartupChannel = null;
      return null;
    }
    final channel = _iptvStartupChannel;
    _iptvStartupChannel = null;
    return channel;
  }

  /// Abort the startup attempt — from BACK, the overlay timeout, or a failure.
  /// Safe to call at any stage, including before anything registered.
  static void cancelIptvStartupChannel() {
    _iptvStartupEpoch++;
    _iptvStartupChannel = null;
    final cancel = cancelIptvStartup;
    if (cancel != null) cancel();
    hideAutoLaunchOverlay?.call();
  }

  /// The epoch an in-flight attempt should keep re-checking.
  static int get iptvStartupEpoch => _iptvStartupEpoch;

  // Store a local Continue Watching item that should be quick-played when
  // TorrentSearchScreen/Home is ready.
  static Map<String, dynamic>? _continueWatchingItemToAutoPlay;

  static void notifyContinueWatchingItemToAutoPlay(Map<String, dynamic> item) {
    final copiedItem = Map<String, dynamic>.from(item);
    final watcher = watchContinueWatchingItem;
    if (watcher != null) {
      _continueWatchingItemToAutoPlay = null;
      unawaited(watcher(copiedItem));
      return;
    }
    _continueWatchingItemToAutoPlay = copiedItem;
  }

  static Map<String, dynamic>? getAndClearContinueWatchingItemToAutoPlay() {
    final item = _continueWatchingItemToAutoPlay;
    _continueWatchingItemToAutoPlay = null;
    return item;
  }

  // Store a fully resolved Quick Play selection that should be auto-played when
  // TorrentSearchScreen/Home is ready.
  static AdvancedSearchSelection? _advancedSearchSelectionToAutoPlay;

  static void notifyAdvancedSearchSelectionToAutoPlay(
    AdvancedSearchSelection selection,
  ) {
    final watcher = watchAdvancedSearchSelection;
    if (watcher != null) {
      _advancedSearchSelectionToAutoPlay = null;
      unawaited(watcher(selection));
      return;
    }
    _advancedSearchSelectionToAutoPlay = selection;
  }

  static AdvancedSearchSelection?
  getAndClearAdvancedSearchSelectionToAutoPlay() {
    final selection = _advancedSearchSelectionToAutoPlay;
    _advancedSearchSelectionToAutoPlay = null;
    return selection;
  }

  // ==========================================================================
  // TV Sidebar Navigation (Android TV only)
  // ==========================================================================
  // Handles focus transitions between sidebar and content screens.
  // - Sidebar calls requestTvContentFocus() when user exits sidebar
  // - Screens call focusTvSidebar() when user is at left edge
  // ==========================================================================

  /// Callback to focus the TV sidebar. Set by main.dart.
  static VoidCallback? focusTvSidebar;

  /// Whether the TV sidebar currently holds focus. Set by main.dart. Lets a
  /// screen avoid auto-focusing its content (stealing focus) when the user has
  /// stepped out to the sidebar while that content was still loading.
  static bool Function()? isTvSidebarFocused;

  /// TV only, set by main.dart: perform a directional-LEFT focus move with the
  /// sidebar as the left-edge fallback (the sidebar's own nodes skip focus
  /// traversal, so a plain `focusInDirection(left)` can never reach it). Use
  /// this instead of `focusInDirection(TraversalDirection.left)` for
  /// programmatic navigation (e.g. the phone-remote fallback path); null off-TV.
  static VoidCallback? tvDirectionalLeft;

  /// TV sidebar focus enter/exit (true = the rail holds focus / is expanded).
  /// Fired by main.dart from the rail's expand signal. Screens with ambient
  /// surfaces (the Home hero trailer) listen to stop them while the user is
  /// in the menu — the hero doesn't change when focus leaves the board, so
  /// they can't infer it from their own focus events.
  static final List<ValueChanged<bool>> _tvSidebarFocusListeners = [];

  static void addTvSidebarFocusListener(ValueChanged<bool> listener) {
    _tvSidebarFocusListeners.add(listener);
  }

  static void removeTvSidebarFocusListener(ValueChanged<bool> listener) {
    _tvSidebarFocusListeners.remove(listener);
  }

  static void notifyTvSidebarFocusChanged(bool focused) {
    for (final listener in List.of(_tvSidebarFocusListeners)) {
      listener(focused);
    }
  }

  /// Latched true the first time the Home board reaches a settled state —
  /// first row batch painted, or a terminal error/empty board (any state where
  /// holding a loading screen longer helps nobody). AppInitializer keeps the
  /// launch splash animating over MainPage until this fires, so the user never
  /// sees the board's own loading state on a cold start. Never reset: it means
  /// "home has been ready at least once this process", not "home is loaded
  /// right now".
  static final ValueNotifier<bool> homeBoardReady = ValueNotifier<bool>(false);

  /// Chrome dim level (0 = normal → 1 = cinema takeover), published by the
  /// Home board while its ambient trailer recedes/takes over the screen.
  /// main.dart's TV shell listens and dims the sidebar rail in lock-step with
  /// the board content, so the WHOLE room goes dark, not just the page. The
  /// publisher must reset it to 0 when it disposes.
  static final ValueNotifier<double> tvChromeDim = ValueNotifier<double>(0);

  /// The focused Home-hero title's dominant colour, published by the Home
  /// board whenever DPAD focus RESTS on a title (null off the Home board).
  /// The TV shell's sidebar rail blends it into its glass background and the
  /// shell's ambient art stage uses it for its tint wash, so the whole room
  /// takes on the film's colour. Constant across trailer start/stop (no
  /// colour flood in/out — user call). The publisher must reset it to null
  /// when it disposes.
  static final ValueNotifier<Color?> tvHeroTint = ValueNotifier<Color?>(null);

  /// URL of the focused Home-hero title's key art, published on the same
  /// rest cadence as [tvHeroTint]. The TV shell renders it as the GLASS
  /// STAGE — a tiny-decode blurred full-screen backdrop BEHIND both the tab
  /// content and the sidebar rail (the Home board's scaffold goes transparent
  /// over it), so every translucent panel reads as frosted glass. Null = the
  /// flat page background. The publisher must reset it to null on dispose.
  static final ValueNotifier<String?> tvAmbientArt = ValueNotifier<String?>(
    null,
  );

  /// True while the Home hero's AMBIENT trailer has frames on screen and the
  /// board has gone lights-off (near-opaque neutral veils over its rows and
  /// hero canvas). The TV shell mirrors the same veil over the sidebar rail
  /// so the WHOLE room dims — without this the rail stayed full-bright beside
  /// a darkened stage. A bool on purpose: the shell animates its own fade
  /// matching the board's veil cadence (slow dim down, fast lights-up). The
  /// publisher must reset it to false when it disposes.
  static final ValueNotifier<bool> tvStageLightsOff = ValueNotifier<bool>(
    false,
  );

  /// Tab-specific content focus handlers for TV navigation.
  /// Each screen registers how to focus its primary/entry element.
  /// Key is the tab index (0=Home, 1=Playlist, 2=Downloads, etc.)
  static final Map<int, VoidCallback> _tvContentFocusHandlers = {};

  /// Currently active tab index for TV navigation
  static int _activeTvTabIndex = 0;

  /// Register a screen's content focus handler for TV navigation.
  /// Call in initState. The handler should focus the screen's primary element.
  static void registerTvContentFocusHandler(
    int tabIndex,
    VoidCallback handler,
  ) {
    _tvContentFocusHandlers[tabIndex] = handler;
  }

  /// Unregister a screen's content focus handler. Call in dispose.
  /// Only removes if the handler matches (prevents race condition when widget rebuilds).
  static void unregisterTvContentFocusHandler(
    int tabIndex,
    VoidCallback handler,
  ) {
    if (_tvContentFocusHandlers[tabIndex] == handler) {
      _tvContentFocusHandlers.remove(tabIndex);
    }
  }

  /// Set the currently active tab index. Call from main.dart when tab changes.
  static void setActiveTvTab(int index) {
    _activeTvTabIndex = index;
  }

  /// The currently active TV tab index. Lets a screen tell whether it's the tab
  /// the user is actually looking at (e.g. to avoid grabbing focus onto an
  /// outgoing page mid tab-transition).
  static int get activeTvTabIndex => _activeTvTabIndex;

  /// Request focus on the current screen's content.
  /// Called by sidebar when user exits (right arrow or select).
  /// Returns true if a handler was found and called.
  static bool requestTvContentFocus() {
    final handler = _tvContentFocusHandlers[_activeTvTabIndex];
    if (handler != null) {
      handler();
      return true;
    }
    return false;
  }
}
