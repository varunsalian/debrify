import '../../../models/metadata_preferences.dart';
import '../../../models/stremio_addon.dart';
import '../data/home_hero_trailer_repository.dart';
import '../models/home_hero_trailer_resolution.dart';

/// Stateless resolution only. Dwell, suppression, loading and native player
/// lifecycle remain with the calling preview owner. Services own their caches.
class HomeHeroTrailerResolver {
  const HomeHeroTrailerResolver(this._repository);
  final HomeHeroTrailerRepository _repository;

  Future<HomeHeroTrailerResolution> resolve(
    StremioMeta item, {
    required bool Function() isCurrent,
  }) async {
    final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    final preferences = await _repository.readPreferences(isCurrent);
    if (preferences == null) {
      return const HomeHeroTrailerResolution.unavailable();
    }
    final candidates = await _repository.selectTrailers(item, () async {
      String? ytId = item.trailerYtId;
      if (ytId == null || ytId.isEmpty) {
        if (imdb == null) return null;
        try {
          final full = await _repository.fetchDetails(imdb, item.type);
          ytId = full?.trailerYtId;
        } catch (_) {
          // Meta failure can still recover through the IMDb backup.
        }
      }
      return ytId;
    }, preferences);
    final ytId = candidates.firstOrNull?.key;
    final allowBackup =
        preferences.provider(MetadataCategory.trailers) ==
            MetadataPreferences.current ||
        preferences.fallback;
    if (!isCurrent()) return const HomeHeroTrailerResolution.retired();
    var streams = (ytId != null && ytId.isNotEmpty)
        ? await _repository.resolveYoutube(ytId)
        : null;
    if (allowBackup &&
        (streams == null || !streams.hasPlayable) &&
        imdb != null) {
      if (!isCurrent()) return const HomeHeroTrailerResolution.retired();
      streams = await _repository.resolveImdb(imdb);
    }
    if (!isCurrent()) return const HomeHeroTrailerResolution.retired();
    if (streams == null || !streams.hasPlayable) {
      return const HomeHeroTrailerResolution.unavailable();
    }
    return HomeHeroTrailerResolution.ready(streams);
  }
}
