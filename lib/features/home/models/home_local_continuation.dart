import '../../../models/stremio_addon.dart';

/// One read-only join of local history and saved playback progress.
/// Metadata identities are borrowed; all result containers are detached.
class HomeLocalContinuation {
  HomeLocalContinuation({
    required List<StremioMeta> items,
    required Set<String> ids,
    required Map<String, double> progress,
    required Map<String, String> episode,
    required Map<String, int> remainingMinutes,
    required Map<String, ({int season, int episode})> episodeRefs,
    required Map<String, String?> addonIds,
  }) : items = List.unmodifiable(items),
       ids = Set.unmodifiable(ids),
       progress = Map.unmodifiable(progress),
       episode = Map.unmodifiable(episode),
       remainingMinutes = Map.unmodifiable(remainingMinutes),
       episodeRefs = Map.unmodifiable(episodeRefs),
       addonIds = Map.unmodifiable(addonIds);

  final List<StremioMeta> items;
  final Set<String> ids;
  final Map<String, double> progress;
  final Map<String, String> episode;
  final Map<String, int> remainingMinutes;
  final Map<String, ({int season, int episode})> episodeRefs;
  final Map<String, String?> addonIds;
}
