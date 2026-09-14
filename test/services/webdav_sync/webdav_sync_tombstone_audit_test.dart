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
        'clearPlaybackStateByImdbId': '_savePlaybackStateMap',
        'unmarkEpisodeAsFinished': '_savePlaybackStateMap',
        'unmarkSeriesAsFinished': '_savePlaybackStateMap',
        'cleanupOldPlaybackState': '_savePlaybackStateMap',
        'clearAllPlaybackData': '_savePlaybackStateMap',
        'clearPlaylistProgress': '_savePlaybackStateMap',
        'purgeUnwatchedResumeGhosts': '_savePlaybackStateMap',
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

      expect(storage, isNot(contains('prefs.remove(_playbackStateKey)')));
      expect(storage, isNot(contains('prefs.remove(_continueWatchingKey)')));
      expect(storage, isNot(contains('prefs.remove(_playlistKey)')));
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
