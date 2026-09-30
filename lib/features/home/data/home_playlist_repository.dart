import '../../../services/storage_service.dart';
import '../models/home_playlist.dart';

/// Keeps the three initial reads parallel, then applies ordering/posters before
/// the existing progress lookup. Raw JSON is confined to this adapter and codec.
class HomePlaylistRepository {
  const HomePlaylistRepository({
    required Future<List<Map<String, dynamic>>> Function() items,
    required Future<Set<String>> Function() favorites,
    required Future<Map<String, String>> Function() posters,
    required String Function(Map<String, dynamic>) posterKey,
    required String Function(Map<String, dynamic>) dedupeKey,
    required Future<Map<String, Map<String, dynamic>>> Function(
      List<Map<String, dynamic>>,
    )
    progress,
  }) : _items = items,
       _favorites = favorites,
       _posters = posters,
       _posterKey = posterKey,
       _dedupeKey = dedupeKey,
       _progress = progress;

  final Future<List<Map<String, dynamic>>> Function() _items;
  final Future<Set<String>> Function() _favorites;
  final Future<Map<String, String>> Function() _posters;
  final String Function(Map<String, dynamic>) _posterKey;
  final String Function(Map<String, dynamic>) _dedupeKey;
  final Future<Map<String, Map<String, dynamic>>> Function(
    List<Map<String, dynamic>>,
  )
  _progress;

  // Legacy playlist writes retain their existing profile resolution and payloads.
  static Future<void> setFavorite(Map<String, dynamic> item, bool favorite) =>
      StorageService.setPlaylistItemFavorited(item, favorite);

  static Future<void> clearProgress({required String title}) =>
      StorageService.clearPlaylistProgress(title: title);

  static String dedupeKey(Map<String, dynamic> item) =>
      StorageService.computePlaylistDedupeKey(item);

  static Future<void> removeByKey(String key) =>
      StorageService.removePlaylistItemByKey(key);

  Future<HomePlaylist?> read({required bool Function() isCurrent}) async {
    if (!isCurrent()) return null;
    final results = await Future.wait<Object>([
      _items(),
      _favorites(),
      _posters(),
    ]);
    if (!isCurrent()) return null;
    final items = [
      for (final item in results[0] as List<Map<String, dynamic>>)
        Map<String, dynamic>.of(item),
    ];
    final favorites = results[1] as Set<String>;
    final posters = results[2] as Map<String, String>;
    items.sort(
      (a, b) =>
          (b['addedAt'] as int? ?? 0).compareTo(a['addedAt'] as int? ?? 0),
    );
    for (final item in items) {
      final poster = posters[_posterKey(item)];
      if (poster != null && poster.isNotEmpty) item['posterUrl'] = poster;
    }
    final progress = await _progress(items);
    if (!isCurrent()) return null;
    return HomePlaylist(
      items: [
        for (final item in items)
          HomePlaylistItem.fromLegacy(item, dedupeKey: _dedupeKey(item)),
      ],
      favorites: favorites,
      progress: {
        for (final entry in progress.entries)
          entry.key: HomePlaylistProgress.fromLegacy(entry.value),
      },
    );
  }
}
