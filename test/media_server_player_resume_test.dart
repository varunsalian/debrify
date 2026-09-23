import 'dart:io';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
          ),
        );
  });
  tearDown(() async {
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    IptvMediaStore.debugResetMigration();
  });

  for (final id in [
    'medialibrary:server:show',
    'custom-series:test',
    'tt123',
    null,
  ]) {
    final isolated = id != null && !id.startsWith('tt');
    test('Flutter final resume fallback respects $id', () async {
      await StorageService.upsertVideoResume('same-stream', {
        'positionMs': 45000,
        'durationMs': 100000,
        'speed': 1.5,
      });
      final missing = await VideoPlayerScreen.readLocalResume(
        contentId: id,
        resumeKey: 'same-stream',
        enhanced: () async => null,
      );
      expect(missing?['positionMs'], isolated ? null : 45000);
      final own = {'positionMs': 12000, 'speed': 1.0};
      expect(
        await VideoPlayerScreen.readLocalResume(
          contentId: id,
          resumeKey: 'same-stream',
          enhanced: () async => own,
        ),
        same(own),
      );
    });

    test('native per-item episode resume respects $id', () async {
      const entry = PlaylistEntry(
        url: 'https://server/episode',
        title: 'Same episode',
      );
      await StorageService.saveVideoPlaybackState(
        videoTitle: VideoPlayerLauncher.resumeIdForEntry(entry),
        videoUrl: entry.url,
        positionMs: 45000,
        durationMs: 100000,
        imdbId: 'tt123',
      );
      final args = VideoPlayerLaunchArgs(
        videoUrl: entry.url,
        title: entry.title,
        contentTitle: 'Show',
        contentType: 'series',
        contentImdbId: id,
        contentSeason: 1,
        contentEpisode: 1,
      );
      expect(
        await VideoPlayerLauncher.debugNativeResumePositions(args, [entry]),
        [isolated ? 0 : 45000],
      );
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Show',
        season: 1,
        episode: 1,
        positionMs: 12000,
        durationMs: 100000,
        imdbId: id,
      );
      expect(
        await VideoPlayerLauncher.debugNativeResumePositions(args, [entry]),
        [12000],
      );
    });
  }

  test('Flutter load path uses the guarded final selection', () {
    final source = File(
      'lib/screens/video_player_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('final state = locallyFinishedMovie');
    final selection = source.substring(
      start,
      source.indexOf('if (state != null)', start),
    );
    expect(selection, contains('VideoPlayerScreen.readLocalResume('));
    expect(selection, contains('contentId: _effectiveContentImdbId'));
    expect(selection, contains('enhanced: _getEnhancedPlaybackState'));
    expect(selection, isNot(contains('StorageService.getVideoResume')));
  });
}
