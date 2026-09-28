import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../../services/main_page_bridge.dart';
import 'discover_preview.dart';

/// Discover's borrowed app-shell registrations. Preview resources remain owned
/// by the route and are disposed after this bridge releases its listeners.
class DiscoverShellBridge {
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
