import 'package:flutter/widgets.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/random_playback_dialog.dart';
import '../models/home_random_playback_preparation.dart';

/// Random-play presentation bridge. The caller supplies preparation and the
/// existing player handoff; opening or rebuilding a view never starts this work.
Future<void> runHomeRandomPlayback({
  required BuildContext context,
  required StremioMeta item,
  required StremioAddon addon,
  required bool Function() isCurrent,
  required Future<HomeRandomPlaybackPreparation> Function(bool continuous)
  prepare,
  required void Function(String message) showMessage,
  required void Function(
    AdvancedSearchSelection selection, {
    required String metadataAddonId,
    required StremioMeta catalogItem,
  })
  launch,
}) async {
  bool current() => context.mounted && isCurrent();
  if (!current()) return;
  final mode = await showRandomPlaybackDialog(context, title: item.name);
  if (!current() || mode == null) return;
  final result = await prepare(mode == RandomPlaybackMode.continuous);
  if (!current()) return;
  switch (result.status) {
    case HomeRandomPlaybackStatus.retired:
      return;
    case HomeRandomPlaybackStatus.loadFailed:
      showMessage('Could not load episodes. Please retry.');
    case HomeRandomPlaybackStatus.noEpisodes:
      showMessage("Couldn't load episodes for \"${item.name}\".");
    case HomeRandomPlaybackStatus.ready:
      // The selected episode can belong to a metadata fallback addon, while
      // playback still receives the original catalog addon/item as before.
      // Keep the existing unawaited handoff: this action ends after dispatch.
      launch(
        result.selection!,
        metadataAddonId: addon.id,
        catalogItem: item.withSourceAddon(addon),
      );
  }
}
