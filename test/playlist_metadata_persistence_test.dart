import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/playback/playlist_metadata_persistence.dart';
import 'package:debrify/services/profiles/privacy_log.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences() : super.withData({});
  bool rejectWrites = false;

  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (rejectWrites && key.endsWith('user_playlist_v1')) {
      throw StateError('https://private.invalid/failure?token=secret');
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Preferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = _Preferences();
    SharedPreferencesStorePlatform.instance = preferences;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StorageService.resetProfileCaches();
    await StorageService.savePlaylistItemsRaw([
      {'title': 'RD', 'rdTorrentId': 'rd'},
      {'title': 'TorBox', 'torboxTorrentId': 42},
    ]);
  });
  tearDown(() {
    StorageService.resetProfileCaches();
    ProfileRuntime.debugReset();
  });

  SeriesPlaylist series({
    String? imdb = 'tt123',
    String? title = 'Show',
    String? poster = 'https://image.invalid/poster?token=secret',
  }) => SeriesPlaylist(
    seriesTitle: title,
    seasons: [],
    allEpisodes: [],
    isSeries: true,
    imdbId: imdb,
  )..showPosterUrl = poster;

  Future<void> saveImdb(SeriesPlaylist value, {String? launch}) =>
      PlaylistMetadataPersistence.saveImdbId(
        value,
        launchContentImdbId: launch,
        rdTorrentId: 'rd',
        torboxTorrentId: null,
        pikpakCollectionId: null,
      );
  Future<void> savePoster(
    SeriesPlaylist value, {
    String? rd = 'rd',
    String? tb,
  }) => PlaylistMetadataPersistence.saveSeriesPoster(
    value,
    rdTorrentId: rd,
    torboxTorrentId: tb,
    pikpakCollectionId: null,
  );

  for (final id in <String?>[null, '', '123', 'TT123']) {
    test('IMDb guard rejects $id without storage writes', () async {
      preferences.rejectWrites = true;
      await saveImdb(series(imdb: id));
      expect(
        (await StorageService.getPlaylistItemsRaw()).first.containsKey(
          'imdbId',
        ),
        isFalse,
      );
    });
  }
  test(
    'prefix-only IMDb and empty launch IMDb retain the current quirks',
    () async {
      await saveImdb(series(imdb: 'tt'), launch: '');
      expect(
        (await StorageService.getPlaylistItemsRaw()).first.containsKey(
          'imdbId',
        ),
        isFalse,
      );
      await saveImdb(series(imdb: 'tt'));
      expect(
        (await StorageService.getPlaylistItemsRaw()).first['imdbId'],
        'tt',
      );
    },
  );
  test('IMDb storage failure propagates to the caller', () async {
    preferences.rejectWrites = true;
    await expectLater(saveImdb(series()), throwsStateError);
  });
  test('null title blocks posters but empty title remains accepted', () async {
    await savePoster(series(title: null));
    expect(
      (await StorageService.getPlaylistItemsRaw()).first.containsKey(
        'posterUrl',
      ),
      isFalse,
    );
    await savePoster(series(title: ''));
    expect(
      (await StorageService.getPlaylistItemsRaw()).first['posterUrl'],
      contains('image.invalid'),
    );
  });
  test('null and empty posters perform no write', () async {
    preferences.rejectWrites = true;
    for (final poster in <String?>[null, '']) {
      await savePoster(series(poster: poster));
    }
    expect(
      (await StorageService.getPlaylistItemsRaw()).first.containsKey(
        'posterUrl',
      ),
      isFalse,
    );
  });
  test(
    'false provider lookup does not prevent the next provider write',
    () async {
      await savePoster(series(), rd: 'missing', tb: '42');
      final items = await StorageService.getPlaylistItemsRaw();
      expect(items.first.containsKey('posterUrl'), isFalse);
      expect(items.last['posterUrl'], contains('image.invalid'));
    },
  );
  test('persistence diagnostics use the installed redacting sink', () async {
    final original = debugPrint;
    final logs = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      PrivacyLog.install();
      await savePoster(series());
      expect(logs, contains('  Poster URL: [private-url]'));
      expect(logs.join(), isNot(contains('image.invalid')));
      preferences.rejectWrites = true;
      await savePoster(series());
      expect(logs.join(), isNot(contains('private.invalid')));
    } finally {
      debugPrint = original;
    }
  });
}
