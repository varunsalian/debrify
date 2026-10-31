// The way into multi-view for the IPTV screens: add or remove a channel,
// open the grid, and the app-wide provider wiring. Legacy IPTV code calls only
// this file, so it never touches the selection or the engines directly.
import 'dart:async';

import 'package:debrify/features/iptv_multiview/application/multi_view_selection_notifier.dart';
import 'package:debrify/features/iptv_multiview/models/multi_view_selection.dart';
import 'package:debrify/features/iptv_multiview/presentation/iptv_multi_view_page.dart';
import 'package:debrify/features/iptv_multiview/presentation/multi_view_engines.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/iptv/multi_view_versions.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Root-scope overrides: the selection belongs to the active profile, and the
/// tile limit follows this device.
List<Override> multiViewAppOverrides() => [
  multiViewOwnerProvider.overrideWithValue(() => ProfileRuntime.scope.value),
  multiViewMaxTilesProvider.overrideWithValue(
    multiViewMaxTiles(currentMultiViewPlatform()),
  ),
];

abstract final class MultiViewLauncher {
  /// Whether this device can show multi-view at all (not tvOS).
  static bool get supported =>
      multiViewMaxTiles(currentMultiViewPlatform()) > 0;

  /// Live channels only: movies and series are not multi-view material.
  static bool eligible(IptvChannel channel) => supported && channel.isLive;

  static MultiViewSelectionNotifier _notifier(BuildContext context) =>
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(multiViewSelectionProvider.notifier);

  static int count(BuildContext context) =>
      _notifier(context).current().channels.length;

  static bool contains(BuildContext context, IptvChannel channel) =>
      _notifier(context).contains(channel);

  /// Adds [channel] and says so, with an Open shortcut once two are picked.
  static void add(
    BuildContext context,
    IptvChannel channel, {
    required Future<void> Function(IptvChannel channel) play,
  }) {
    final notifier = _notifier(context);
    final result = notifier.add(channel);
    final count = notifier.current().channels.length;
    final max = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(multiViewMaxTilesProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          MultiViewAddResult.added => 'Added to multi-view ($count of $max)',
          MultiViewAddResult.duplicate => 'Already in multi-view',
          MultiViewAddResult.full => 'Multi-view is full ($max channels)',
        }),
        persist: false, // auto-hide, as before Flutter 3.44
        action: count >= 2
            ? SnackBarAction(
                label: 'Open',
                onPressed: () => unawaited(open(context, play: play)),
              )
            : null,
      ),
    );
  }

  static void remove(BuildContext context, IptvChannel channel) {
    final notifier = _notifier(context);
    final index = notifier.current().channels.indexWhere(
      (c) => c.url == channel.url,
    );
    if (index >= 0) notifier.remove(index);
  }

  /// Opens the grid. The IPTV preview behind it stops first (as for any
  /// player launch) so its decoder is free for the tiles.
  static Future<void> open(
    BuildContext context, {
    required Future<void> Function(IptvChannel channel) play,
  }) async {
    MainPageBridge.notifyPlayerLaunching();
    final released = Completer<void>();
    final chosen = await Navigator.of(context).push<IptvChannel>(
      MaterialPageRoute<IptvChannel>(
        builder: (_) => IptvMultiViewPage(
          engineFactory: createMultiViewEngine,
          versions: findMultiViewVersions,
          released: released,
        ),
      ),
    );
    // Nothing else may decode until every tile let go of its decoder.
    await released.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    if (chosen != null && context.mounted) {
      await play(chosen);
      return;
    }
    // The grid counted as playback; its end lets the preview come back.
    MainPageBridge.notifyContentPlaybackStopped();
  }
}
