import 'package:debrify/features/home/data/home_playlist_repository.dart';

typedef PlaylistRows = List<Map<String, dynamic>>;
Map<String, dynamic> playlistItem(
  String id, {
  String? title,
  int addedAt = 0,
}) => {'id': id, 'title': title ?? id, 'kind': 'single', 'addedAt': addedAt};
HomePlaylistRepository repository({
  required Future<PlaylistRows> Function() items,
  Future<Set<String>> Function()? favorites,
  Future<Map<String, String>> Function()? posters,
  Future<Map<String, Map<String, dynamic>>> Function(PlaylistRows)? progress,
}) => HomePlaylistRepository(
  items: items,
  favorites: favorites ?? () async => {},
  posters: posters ?? () async => {},
  posterKey: (item) => 'poster:${item['id']}',
  dedupeKey: (item) => 'play:${item['id']}',
  progress: progress ?? (_) async => {},
);
