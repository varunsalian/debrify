import 'package:flutter/foundation.dart';

import '../models/rd_torrent.dart';
import '../models/torbox_torrent.dart';

enum TorboxQuickAction {
  play,
  download,
  files,
}

class MainPageBridge {
  static void Function(int index)? switchTab;
  static void Function(RDTorrent torrent)? openDebridOptions;
  static void Function(TorboxTorrent torrent, TorboxQuickAction action)?
      openTorboxAction;
  static Future<void> Function(Map<String, dynamic> result, String torrentName, String apiKey)? handleRealDebridResult;
  static Future<void> Function(TorboxTorrent torrent)? handleTorboxResult;

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
}
