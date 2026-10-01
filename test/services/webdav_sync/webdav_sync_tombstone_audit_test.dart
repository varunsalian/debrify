import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every audited hot deletion API reaches its central tombstone helper',
    () {
      final storage = File(
        'lib/services/storage_service.dart',
      ).readAsStringSync();
      final sources = File(
        'lib/services/series_source_service.dart',
      ).readAsStringSync();

      const storageAudit = <String, String>{
        'removeContinueWatchingItem': '_saveContinueWatchingItems',
        'clearContinueWatching': '_saveContinueWatchingItems',
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
          _methodBody(storage, entry.key),
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

      final forbiddenRemoval = RegExp(
        r'\bprefs\.remove\(\s*'
        r'(?:(?:PlaybackStateStore|ContinueWatchingStorage|PlaylistStorage)\.)?'
        r'(?:_?playbackStateKey|_?continueWatchingKey|_?playlistKey)\s*\)',
      );
      expect(forbiddenRemoval.hasMatch(storage), isFalse);
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
