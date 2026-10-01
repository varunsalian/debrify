import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../models/mdblist_list_choice.dart';
import '../../../services/main_page_bridge.dart';
import 'discover_preview.dart';

/// Discover's borrowed app-shell registrations. Preview resources remain owned
/// by the route and are disposed after this bridge releases its listeners.
class DiscoverShellBridge {
  static void openMdblistList(MdblistListChoice choice) {
    MainPageBridge.pendingMdblistListOpen = {
      'id': choice.id,
      'name': choice.name,
      'ownerName': choice.ownerName,
      'itemCount': choice.itemCount,
      'liked': choice.liked,
      'likes': choice.likes,
    };
    // Discover tab — main.dart `case 18`.
    MainPageBridge.switchTab?.call(MainTab.discover);
  }

  static void claimMdblistList(ValueChanged<MdblistListChoice> accept) {
    final pending = MainPageBridge.pendingMdblistListOpen;
    if (pending != null) {
      MainPageBridge.pendingMdblistListOpen = null;
      accept(
        MdblistListChoice(
          id: (pending['id'] as num?)?.toInt() ?? -1,
          name: pending['name'] as String? ?? 'Untitled list',
          ownerName: pending['ownerName'] as String?,
          itemCount: (pending['itemCount'] as num?)?.toInt() ?? 0,
          liked: pending['liked'] == true,
          likes: (pending['likes'] as num?)?.toInt() ?? 0,
        ),
      );
    }
  }

  DiscoverShellBridge({
    required this.readPreview,
    required this.isTelevision,
    required this.onCardSettings,
    required this.onLayout,
    required Future<void> Function() loadLayout,
  }) {
    MainPageBridge.discoverCardSettingsChanged = onCardSettings;
    if (isTelevision) {
      preview.takeover.addListener(_relayChromeDim);
      preview.observePlayback();
      unawaited(loadLayout());
      MainPageBridge.discoverLayoutChanged = onLayout;
    }
  }

  final DiscoverPreview Function() readPreview;
  late final DiscoverPreview preview = readPreview();
  final bool isTelevision;
  final VoidCallback onCardSettings;
  final VoidCallback onLayout;

  void _relayChromeDim() =>
      MainPageBridge.tvChromeDim.value = preview.takeover.value;

  void dispose() {
    if (MainPageBridge.discoverCardSettingsChanged == onCardSettings) {
      MainPageBridge.discoverCardSettingsChanged = null;
    }
    if (!isTelevision) return;
    preview.takeover.removeListener(_relayChromeDim);
    preview.stopObservingPlayback();
    // A newer Discover route may already own the shared callback slots.
    if (MainPageBridge.discoverLayoutChanged == onLayout) {
      MainPageBridge.discoverLayoutChanged = null;
    }
    // Unmount can run while the tree is locked; retain the original deferred
    // reset rather than notifying sidebar listeners synchronously in dispose.
    if (MainPageBridge.tvChromeDim.value != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MainPageBridge.tvChromeDim.value = 0;
      });
    }
  }
}
