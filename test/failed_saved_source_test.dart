import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/failed_saved_source.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/resolved_playback_link_cache.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SeriesSource pin(
    String addon, {
    String? group = 'group',
    String stream = 'stream',
  }) => SeriesSource(
    torrentHash: '',
    torrentName: 'File',
    debridService: SeriesSource.addonDirectService,
    debridTorrentId: '',
    boundAt: 0,
    addonId: 'addon',
    addonKey: addon,
    bingeGroup: group,
    streamKey: stream,
  );
  Torrent source() => Torrent(
    rowid: 1,
    infohash: '',
    name: 'File',
    sizeBytes: 0,
    createdUnix: 0,
    seeders: 0,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
    source: 'addon',
    streamType: StreamType.directUrl,
    directUrl: 'https://test/failed',
    stremioAddonKey: 'one',
    stremioBingeGroup: 'group',
    stremioStreamKey: 'stream',
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'unpin-test');
  });
  tearDown(SecretVault.debugReset);
  for (final failPin in [false, true]) {
    for (final failCache in [false, true]) {
      test(
        'cleanup continues after storage failures: pin=$failPin cache=$failCache',
        () async {
          final events = <String>[];
          await FailedSavedSource.cleanup(
            removePin: () async {
              events.add('pin');
              if (failPin) throw StateError('pin write failed');
            },
            removeCache: () async {
              events.add('cache');
              if (failCache) throw StateError('cache write failed');
            },
          );
          events.add('recover');
          expect(events, ['pin', 'cache', 'recover']);
        },
      );
    }
  }
  test('matches only the failed configured addon and binding', () {
    expect(FailedSavedSource.matches(pin('one'), source()), isTrue);
    expect(FailedSavedSource.matches(pin('two'), source()), isFalse);
    expect(
      FailedSavedSource.matches(pin('one', group: 'other'), source()),
      isFalse,
    );
    expect(
      FailedSavedSource.matches(pin('one', group: null), source()),
      isTrue,
    );
    expect(
      FailedSavedSource.matches(
        pin('one', group: null, stream: 'other'),
        source(),
      ),
      isFalse,
    );
  });
  test('missing episode leaves a working season pack pinned', () async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      'series_source_tt123',
      jsonEncode([pin('one').toJson()]),
    );
    await FailedSavedSource.forget(
      'tt123',
      source(),
      reason: 'playlist-missing-episode',
    );
    expect((await SeriesSourceService.getSources('tt123')).length, 1);
  });
  test('forgets pin and cached URL while preserving other sources', () async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      'series_source_tt123',
      jsonEncode([pin('one').toJson(), pin('two').toJson()]),
    );
    await prefs.setString(
      ResolvedPlaybackLinkCache.preferenceKey,
      await SecretVault.seal(
        jsonEncode({
          'failed': {'source': source().toJson()},
          'other': {
            'source': {'direct_url': 'https://test/other'},
          },
        }),
      ),
    );
    await FailedSavedSource.forget('tt123', source());
    expect(
      (await SeriesSourceService.getSources('tt123')).map((s) => s.addonKey),
      ['two'],
    );
    final cache =
        jsonDecode(
              (await SecretVault.open(
                prefs.getString(ResolvedPlaybackLinkCache.preferenceKey),
              ))!,
            )
            as Map;
    expect(cache.keys, ['other']);
    // Repeated delivery is harmless; no persistent exclusion is written.
    await FailedSavedSource.forget('tt123', source());
    expect(prefs.getString('native_playback_source_failures_v1'), isNull);
  });
}
