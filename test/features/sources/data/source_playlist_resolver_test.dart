import 'dart:async';

import 'package:debrify/features/sources/data/source_playlist_resolver.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'source_acquisition_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'playlist-resolution');
    SharedPreferences.setMockInitialValues({
      'real_debrid_api_key': 'rd-fixture',
      'torbox_api_key': 'tb-fixture',
      'premiumize_api_key': 'pm-fixture',
      'alldebrid_api_key': 'ad-fixture',
      'file_selection': 'all',
    });
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });

  for (final provider in ['debrid', 'torbox', 'premiumize', 'alldebrid']) {
    for (final retired in [false, true]) {
      test(
        '$provider playlist acquisition preserves ownership; retired=$retired',
        () async {
          final f = fixture.Fixture(provider, 'pack');
          if (retired) f.onRequest = (_) => ProfileSessionMemory.clearAll();
          final client = MockClient(f.respond);
          addTearDown(client.close);
          final resolver = SourcePlaylistResolver(
            owner: ProfileSessionMemory.captureOwner(),
            provider: provider,
            canContinue: () => true,
            chooseProvider: (_) async =>
                throw StateError('fixed provider must not select'),
          );
          final result = await http.runWithClient(
            () => resolver.resolve(fixture.torrent),
            () => client,
          );
          if (retired) {
            expect(result, isNull);
            // A fresh RD torrent abandoned by the retired add is removed.
            expect(f.requests, hasLength(provider == 'debrid' ? 2 : 1));
            expect(
              f.paths.where((p) => p.contains('/delete')),
              provider == 'debrid' ? [endsWith('/torrents/delete/owned')] : [],
            );
          } else {
            expect(result, hasLength(2));
            expect(
              result!.map((e) => e.title),
              provider == 'debrid'
                  ? ['Fixture.S01E02.mkv', 'Fixture.S01E01.mkv']
                  : ['Fixture.S01E01.mkv', 'Fixture.S01E02.mkv'],
            );
            expect(result.any((e) => e.url == 'https://stream.test/1'), isTrue);
            expect(f.paths.where((p) => p.contains('/delete')), isEmpty);
          }
        },
      );
    }
  }

  for (final retirement in ['close', 'profile']) {
    test('$retirement while selecting provider prevents acquisition', () async {
      final entered = Completer<void>();
      final release = Completer<String?>();
      var active = true;
      var requests = 0;
      final resolver = SourcePlaylistResolver(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => active,
        chooseProvider: (current) {
          expect(current(), isTrue);
          entered.complete();
          return release.future;
        },
      );
      final client = MockClient((_) async {
        requests++;
        throw StateError('retired request');
      });
      addTearDown(client.close);
      final pending = http.runWithClient(
        () => resolver.resolve(fixture.torrent),
        () => client,
      );
      await entered.future;
      if (retirement == 'close') {
        active = false;
      } else {
        ProfileSessionMemory.clearAll();
      }
      release.complete('debrid');
      expect(await pending, isNull);
      expect(requests, 0);
    });
  }

  test(
    'direct streams preserve headers and bypass provider selection',
    () async {
      var active = true;
      var selections = 0;
      final resolver = SourcePlaylistResolver(
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => active,
        chooseProvider: (_) async {
          selections++;
          return 'debrid';
        },
      );
      final direct = Torrent(
        rowid: 0,
        infohash: 'url:fixture',
        name: 'Direct',
        sizeBytes: 0,
        createdUnix: 0,
        seeders: 0,
        leechers: 0,
        completed: 0,
        scrapedDate: 0,
        streamType: StreamType.directUrl,
        directUrl: 'https://fixture.test/movie',
        httpHeaders: {'Referer': 'https://fixture.test'},
      );
      final result = await resolver.resolve(direct);
      expect(result!.single.url, direct.directUrl);
      expect(result.single.httpHeaders, direct.httpHeaders);
      expect(selections, 0);
      active = false;
      expect(await resolver.resolve(direct), isNull);
    },
  );
  test(
    'superseded switch stops provider requests while the profile stays active',
    () async {
      final owner = ProfileSessionMemory.captureOwner();
      var generation = 1;
      final f = fixture.Fixture('debrid', 'pack');
      f.onRequest = (_) {
        generation = 2;
      };
      final client = MockClient(f.respond);
      addTearDown(client.close);
      final resolver = SourcePlaylistResolver(
        owner: owner,
        provider: 'debrid',
        canContinue: () => true,
        chooseProvider: (_) async => 'debrid',
      );
      final result = await http.runWithClient(
        () => resolver.resolve(
          fixture.torrent,
          canContinue: () => generation == 1,
        ),
        () => client,
      );
      expect(result, isNull);
      // The superseded add removes only its own fresh torrent.
      expect(f.requests, hasLength(2));
      expect(ProfileSessionMemory.captureOwner(), owner);
      expect(f.paths.where((path) => path.contains('/delete')), [
        endsWith('/torrents/delete/owned'),
      ]);
    },
  );
}
