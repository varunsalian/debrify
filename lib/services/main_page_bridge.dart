import 'package:flutter/foundation.dart';

import '../models/rd_torrent.dart';
import '../models/torbox_torrent.dart';

class MainPageBridge {
  static void Function(int index)? switchTab;
  static void Function(RDTorrent torrent)? openDebridOptions;
  static void Function(TorboxTorrent torrent)? openTorboxFolder;
  static void Function(String fileId, String folderName)? openPikPakFolder;
  static Future<void> Function(Map<String, dynamic> result, String torrentName, String apiKey)? handleRealDebridResult;
  static Future<void> Function(TorboxTorrent torrent)? handleTorboxResult;
  static VoidCallback? hideAutoLaunchOverlay;
  static Future<void> Function(Map<String, dynamic> playlistItem)? playPlaylistItem;

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

  // Store a playlist item that should be auto-played when PlaylistScreen initializes
  static Map<String, dynamic>? _playlistItemToAutoPlay;

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

  static void notifyPlayerLaunching() {
    hideAutoLaunchOverlay?.call();
  }

  static void notifyAutoLaunchFailed([String? reason]) {
    debugPrint('MainPageBridge: Auto-launch failed: $reason');
    hideAutoLaunchOverlay?.call();
  }

  static void notifyPlaylistItemToAutoPlay(Map<String, dynamic> item) {
    _playlistItemToAutoPlay = item;
  }

  static Map<String, dynamic>? getAndClearPlaylistItemToAutoPlay() {
    final item = _playlistItemToAutoPlay;
    _playlistItemToAutoPlay = null;
    return item;
  }
}
