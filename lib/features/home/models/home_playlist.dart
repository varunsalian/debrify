/// Typed Home presentation with an explicit codec boundary for legacy actions.
/// Unknown provider fields survive handoff, but never become mutable row state.
class HomePlaylistItem {
  HomePlaylistItem.fromLegacy(
    Map<String, dynamic> item, {
    required this.dedupeKey,
  }) : title = item['title'] as String? ?? 'Unknown',
       posterUrl = item['posterUrl'] as String?,
       isCollection = (item['kind'] as String?) != 'single',
       _payload = _freeze(item) as Map<String, Object?>;

  final String dedupeKey;
  final String title;
  final String? posterUrl;
  final bool isCollection;
  final Map<String, Object?> _payload;

  /// Detached mutable JSON for the existing menu/player/storage entry points.
  /// Their mutations cannot alter an already published Home snapshot.
  Map<String, dynamic> toLegacyItem() =>
      _copy(_payload) as Map<String, dynamic>;

  static Object? _freeze(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable({
        for (final entry in value.entries)
          entry.key as String: _freeze(entry.value),
      });
    }
    if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw const FormatException('Playlist payload must contain JSON values');
  }

  static Object? _copy(Object? value) {
    if (value is Map<String, Object?>) {
      return <String, dynamic>{
        for (final entry in value.entries) entry.key: _copy(entry.value),
      };
    }
    if (value is List) {
      return <dynamic>[for (final entry in value) _copy(entry)];
    }
    return value;
  }
}

class HomePlaylistProgress {
  HomePlaylistProgress.fromLegacy(Map<String, dynamic> progress)
    : positionMs = (progress['positionMs'] as num?)?.toInt(),
      durationMs = (progress['durationMs'] as num?)?.toInt();

  final int? positionMs;
  final int? durationMs;

  double? get fraction {
    final position = positionMs;
    final duration = durationMs;
    if (position == null || duration == null || duration <= 0) return null;
    return (position / duration).clamp(0.0, 1.0);
  }
}

class HomePlaylist {
  const HomePlaylist.empty()
    : items = const [],
      favorites = const {},
      progress = const {};

  HomePlaylist({
    required List<HomePlaylistItem> items,
    required Set<String> favorites,
    required Map<String, HomePlaylistProgress> progress,
  }) : items = List.unmodifiable(items),
       favorites = Set.unmodifiable(favorites),
       progress = Map.unmodifiable(progress);

  final List<HomePlaylistItem> items;
  final Set<String> favorites;
  final Map<String, HomePlaylistProgress> progress;

  double? progressFor(HomePlaylistItem item) =>
      progress[item.dedupeKey]?.fraction;
  bool hasProgress(HomePlaylistItem item) =>
      progress.containsKey(item.dedupeKey);
  bool isFavorite(HomePlaylistItem item) => favorites.contains(item.dedupeKey);
}
