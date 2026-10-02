import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every audited hot deletion API reaches its central tombstone helper',
    () {
      const storageOwners = <String, String>{
        'removeContinueWatchingItem':
            'lib/services/storage/continue_watching_storage.dart',
        'clearContinueWatching':
            'lib/services/storage/continue_watching_storage.dart',
        'unmarkMovieAsFinished':
            'lib/services/storage/movie_progress_storage.dart',
        'setSeriesExplicitlyWatched':
            'lib/services/storage/movie_progress_storage.dart',
        'clearPlaybackStateByImdbId':
            'lib/services/storage/playback_cleanup_storage.dart',
        'unmarkEpisodeAsFinished':
            'lib/services/storage/episode_completion_storage.dart',
        'unmarkSeriesAsFinished':
            'lib/services/storage/episode_completion_storage.dart',
        'cleanupOldPlaybackState':
            'lib/services/storage/playback_cleanup_storage.dart',
        'clearAllPlaybackData':
            'lib/services/storage/playback_cleanup_storage.dart',
        'clearPlaylistProgress':
            'lib/services/storage/playlist_progress_storage.dart',
        'purgeUnwatchedResumeGhosts':
            'lib/services/storage/completion_migration_storage.dart',
        'savePlaylistItemsRaw': 'lib/services/storage/playlist_storage.dart',
        'removePlaylistItemByKey': 'lib/services/storage/playlist_storage.dart',
        'clearPlaylist': 'lib/services/storage/playlist_storage.dart',
        'setPlaylistItemFavorited':
            'lib/services/storage/playlist_preferences_storage.dart',
        'clearAllPlaylistMetadata':
            'lib/services/storage/playlist_storage.dart',
      };
      final storageSources = <String, String>{
        for (final path in storageOwners.values.toSet())
          path: File(path).readAsStringSync(),
      };
      final sources = File(
        'lib/services/series_source_service.dart',
      ).readAsStringSync();

      const storageAudit = <String, String>{
        'removeContinueWatchingItem': 'saveContinueWatchingItems',
        'clearContinueWatching': 'saveContinueWatchingItems',
        'unmarkMovieAsFinished': 'WebDavSyncTombstoneRecorder',
        'setSeriesExplicitlyWatched': 'WebDavSyncTombstoneRecorder',
        'clearPlaybackStateByImdbId': 'PlaybackStateStore.savePlaybackStateMap',
        'unmarkEpisodeAsFinished': 'PlaybackStateStore.savePlaybackStateMap',
        'unmarkSeriesAsFinished': 'PlaybackStateStore.savePlaybackStateMap',
        'cleanupOldPlaybackState': 'PlaybackStateStore.savePlaybackStateMap',
        'clearAllPlaybackData': 'PlaybackStateStore.savePlaybackStateMap',
        'clearPlaylistProgress': 'PlaybackStateStore.savePlaybackStateMap',
        'purgeUnwatchedResumeGhosts': 'PlaybackStateStore.savePlaybackStateMap',
        'savePlaylistItemsRaw': 'WebDavSyncTombstoneRecorder',
        'removePlaylistItemByKey': 'savePlaylistItemsRaw',
        'clearPlaylist': 'savePlaylistItemsRaw',
        'setPlaylistItemFavorited': 'WebDavSyncTombstoneRecorder',
        'clearAllPlaylistMetadata': 'WebDavSyncTombstoneRecorder',
      };
      const sourceAudit = <String, String>{
        'removeSourceByHash': 'WebDavSyncTombstoneRecorder',
        'removeSourceEntry': 'WebDavSyncTombstoneRecorder',
        'removeAllSources': 'WebDavSyncTombstoneRecorder',
        'setSources': 'WebDavSyncTombstoneRecorder',
      };

      for (final entry in storageAudit.entries) {
        expect(
          _methodBody(storageSources[storageOwners[entry.key]]!, entry.key),
          contains(entry.value),
          reason: '${entry.key} bypasses the audited deletion helper',
        );
      }
      for (final entry in sourceAudit.entries) {
        expect(
          _methodBody(sources, entry.key),
          contains(entry.value),
          reason: '${entry.key} bypasses the audited deletion helper',
        );
      }

      // The original scanned the whole of storage_service.dart; scan every
      // file that replaced it, not only the audited owners.
      final forbiddenRemoval = RegExp(
        r'\bprefs\.remove\(\s*'
        r'(?:\w+\.)?'
        r'(?:_?playbackStateKey|_?continueWatchingKey|_?playlistKey)\s*\)',
      );
      final storageFiles = Directory('lib/services/storage')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(storageFiles, isNotEmpty);
      for (final file in storageFiles) {
        expect(
          forbiddenRemoval.hasMatch(file.readAsStringSync()),
          isFalse,
          reason: file.path,
        );
      }
    },
  );
}

String _methodBody(String source, String name) {
  final start = source.indexOf(RegExp('static Future<[^>]*> $name\\b'));
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: 'Audited API $name was removed/renamed',
  );
  final next = source.indexOf(
    RegExp(r'\n  static (?:Future|void|bool|String|int)'),
    start + 1,
  );
  return source.substring(start, next < 0 ? source.length : next);
}
