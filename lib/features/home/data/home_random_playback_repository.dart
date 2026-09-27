import 'dart:async';

import '../../../models/media_identity.dart';
import '../../../models/stremio_addon.dart';
import '../models/home_random_playback_preparation.dart';
import 'home_random_episode_selector.dart';

/// Stateless metadata preparation. Each explicit call has its own live guard;
/// overlapping active actions retain their original independent behavior.
class HomeRandomPlaybackRepository {
  const HomeRandomPlaybackRepository({
    required this.nativeAddon,
    required this.readAddons,
    required this.fetchEpisodes,
    required this.recordInventory,
    required this.selector,
    required this.isOwnerCurrent,
    required this.onInventoryError,
  });

  final StremioAddon nativeAddon;
  final Future<List<StremioAddon>> Function() readAddons;
  final Future<List<Map<String, dynamic>>?> Function(StremioAddon, String)
  fetchEpisodes;
  final Future<void> Function(
    String,
    String,
    List<Map<String, dynamic>>,
    bool Function(),
  )
  recordInventory;
  final HomeRandomEpisodeSelector selector;
  final bool Function() isOwnerCurrent;
  final void Function(Object, StackTrace) onInventoryError;

  Future<StremioAddon?> _metadataAddon(StremioAddon preferred) async {
    if (preferred.id == nativeAddon.id) return preferred;
    if (preferred.resources.contains('meta') && preferred.baseUrl.isNotEmpty) {
      return preferred;
    }
    for (final addon in await readAddons()) {
      if (addon.resources.contains('meta') && addon.baseUrl.isNotEmpty) {
        return addon;
      }
    }
    return null;
  }

  Future<HomeRandomPlaybackPreparation> prepare({
    required StremioMeta item,
    required StremioAddon addon,
    required String? progressId,
    required bool continuous,
    required bool Function() isCurrent,
  }) async {
    bool current() => isOwnerCurrent() && isCurrent();
    if (!current()) return const HomeRandomPlaybackPreparation.retired();
    final metadataAddon =
        MediaIdentity.isNative(item.progressId) && addon.baseUrl.isEmpty
        ? nativeAddon
        : await _metadataAddon(addon);
    if (!current()) return const HomeRandomPlaybackPreparation.retired();
    // A fallback addon cannot interpret the origin's private catalog ID.
    final contentId = metadataAddon != null && metadataAddon.id == addon.id
        ? item.id
        : (progressId ?? item.id);
    List<Map<String, dynamic>>? videos;
    try {
      videos = metadataAddon == null
          ? null
          : await fetchEpisodes(metadataAddon, contentId);
    } catch (_) {
      return current()
          ? const HomeRandomPlaybackPreparation.loadFailed()
          : const HomeRandomPlaybackPreparation.retired();
    }
    if (!current()) return const HomeRandomPlaybackPreparation.retired();
    if (videos != null && progressId != null) {
      // Recording begins before selection, but never delays playback. Forward
      // the live guard through the writer's existing preference commit barrier.
      unawaited(
        recordInventory(
          progressId,
          item.name,
          videos,
          current,
        ).catchError(onInventoryError),
      );
    }
    final selection = selector.select(
      item: item,
      metadataAddon: metadataAddon,
      contentId: contentId,
      progressId: progressId,
      videos: videos,
      continuous: continuous,
    );
    return selection == null
        ? const HomeRandomPlaybackPreparation.noEpisodes()
        : HomeRandomPlaybackPreparation.ready(selection);
  }
}
