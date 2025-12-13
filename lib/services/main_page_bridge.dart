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
