import '../../../models/advanced_search_selection.dart';
import '../../../models/stremio_addon.dart';

typedef HomeCatalogEpisodeVideoReader =
    Future<String?> Function({
      required StremioAddon addon,
      required String imdbId,
      required String catalogId,
      required int season,
      required int episode,
    });

/// Resolves an episode's exact addon identity before catalog play/source browse.
/// Transport caching and canonical identity rules remain with their dependencies.
class HomeCatalogEpisodeIdentity {
  const HomeCatalogEpisodeIdentity({
    required this.readVideoId,
    required this.isCanonicalCatalog,
    required this.isCanonicalEpisode,
    required this.isOwnerCurrent,
  });

  final HomeCatalogEpisodeVideoReader readVideoId;
  final bool Function(String, String) isCanonicalCatalog;
  final bool Function(String, String, int, int) isCanonicalEpisode;
  final bool Function() isOwnerCurrent;

  /// Null means the originating action retired; it must not launch or browse.
  Future<AdvancedSearchSelection?> resolve(
    AdvancedSearchSelection selection,
    StremioMeta item,
    StremioAddon addon, {
    required bool Function() isCurrent,
  }) async {
    bool current() => isOwnerCurrent() && isCurrent();
    if (!current()) return null;
    final season = selection.season;
    final episode = selection.episode;
    if (!selection.isSeries || season == null || episode == null) {
      return selection;
    }
    final videoId = await readVideoId(
      addon: addon,
      imdbId: selection.imdbId,
      catalogId: item.id,
      season: season,
      episode: episode,
    );
    if (!current()) return null;
    if (videoId == null || videoId.isEmpty) {
      // Retain an unknown/custom origin so playback can retry or fail unavailable
      // instead of silently playing the ordinary IMDb edit of the episode.
      if (!isCanonicalCatalog(item.id, selection.imdbId)) {
        return selection.withStremioEpisodeIdentity(
          addonId: addon.id,
          addonKey: addon.sourceBindingKey,
          catalogId: item.id,
          videoId: '',
        );
      }
      return selection;
    }
    if (isCanonicalEpisode(selection.imdbId, videoId, season, episode)) {
      return selection;
    }
    return selection.withStremioEpisodeIdentity(
      addonId: addon.id,
      addonKey: addon.sourceBindingKey,
      catalogId: item.id,
      videoId: videoId,
    );
  }
}
