import '../../../utils/concurrency.dart';
import '../models/home_episode_artwork.dart';

/// Bounded optional episode-still reads, independent of widgets and Riverpod.
class HomeEpisodeArtworkRepository {
  const HomeEpisodeArtworkRepository(this.resolve);
  final HomeEpisodeArtworkReader resolve;

  Future<Map<String, String>?> read(
    Map<String, HomeEpisodeReference> refs, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    final resolved = await mapWithConcurrency(refs.entries, (entry) async {
      if (!isCurrent()) return (id: entry.key, art: null as String?);
      final art = await resolve(
        imdbId: entry.key,
        season: entry.value.season,
        episode: entry.value.episode,
      );
      return (id: entry.key, art: art);
    }, concurrency: 3);
    if (!isCurrent()) return null;
    return Map.unmodifiable({
      for (final item in resolved)
        if (item.art != null && item.art!.isNotEmpty) item.id: item.art!,
    });
  }
}
