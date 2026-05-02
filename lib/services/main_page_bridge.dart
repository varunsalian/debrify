import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/rd_torrent.dart';
import '../models/torbox_torrent.dart';

class MainPageBridge {
  static void Function(int index)? switchTab;
  static void Function(RDTorrent torrent)? openDebridOptions;
  static void Function(TorboxTorrent torrent)? openTorboxFolder;
  static void Function(String fileId, String folderName)? openPikPakFolder;

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
  static Future<void> Function(String channelId)? watchDebrifyTvChannel;
  static Future<void> Function(String channelId)? watchStremioTvChannel;
  static Future<void> Function(Map<String, dynamic> item)?
  watchContinueWatchingItem;

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

  /// Unregister a tab's back handler. Call in dispose of tab screens.
  static void unregisterTabBackHandler(String key) {
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

  static void notifyPlayerLaunching() {
    hideAutoLaunchOverlay?.call();
  }

  static void notifyAutoLaunchFailed([String? reason]) {
    debugPrint('MainPageBridge: Auto-launch failed: $reason');
    hideAutoLaunchOverlay?.call();
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

  // ==========================================================================
  // TV Sidebar Navigation (Android TV only)
  // ==========================================================================
  // Handles focus transitions between sidebar and content screens.
  // - Sidebar calls requestTvContentFocus() when user exits sidebar
  // - Screens call focusTvSidebar() when user is at left edge
  // ==========================================================================

  /// Callback to focus the TV sidebar. Set by main.dart.
  static VoidCallback? focusTvSidebar;

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
