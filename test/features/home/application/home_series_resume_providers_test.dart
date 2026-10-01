import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/home/application/home_playback_providers.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt_continue_watching_item.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const show = StremioMeta(id: 'tt123', type: 'series', name: 'Exact Title');
String history({int season = 2, int episode = 3, String id = 'tt123'}) =>
    jsonEncode({
      'series_exact_title': {
        'type': 'series',
        'imdbId': id,
        'seasons': {
          '$season': {
            '$episode': {
              'positionMs': 250,
              'durationMs': 1000,
              'updatedAt': 1000,
            },
          },
        },
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'series-resume-fixture');
    TraktService.instance.resetProfileScope();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });

  test(
    'stateless retained factory reads fresh local history and stops after retirement',
    () async {
      final container = ProviderContainer.test();
      final repository = container.read(
        homeSeriesResumeRepositoryProvider(ProfileSessionMemory.captureOwner()),
      );
      await container.pump();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playback_state_v1', history());
      expect(await repository.local(show, 'tt123', isCurrent: () => true), (
        season: 2,
        episode: 3,
        pct: 25.0,
        tsMs: 1000,
        finished: false,
      ));
      // Exact-ID miss falls back to the actual legacy title-key reader.
      await prefs.setString(
        'playback_state_v1',
        history(season: 4, episode: 5, id: 'tt999'),
      );
      expect(await repository.local(show, 'tt123', isCurrent: () => true), (
        season: 4,
        episode: 5,
        pct: 25.0,
        tsMs: 1000,
        finished: false,
      ));
      expect(
        await repository.local(show, 'tmdb:123', isCurrent: () => true),
        isNull,
      );
      ProfileSessionMemory.clearAll();
      expect(
        await repository.local(show, 'tt123', isCurrent: () => true),
        isNull,
      );
      expect(
        prefs.getString('playback_state_v1'),
        history(season: 4, episode: 5, id: 'tt999'),
      );
    },
  );

  test(
    'real local reads use captured profile even under a foreign scope',
    () async {
      ProfileRuntime.debugReset();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final temp = await Directory.systemTemp.createTemp(
        'series-resume-profile-',
      );
      final registry = await ProfileRegistry.open(
        path: '${temp.path}/profiles.db',
      );
      addTearDown(() async {
        ProfileBootstrap.debugInstallRegistry(null);
        await registry.close();
        await temp.delete(recursive: true);
      });
      final profile = await registry.createProfile(
        name: 'Series',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: profile.id,
        migratedLegacyInstall: false,
      );
      ProfileBootstrap.debugInstallRegistry(registry);
      final scope = ProfileScope(
        profileId: profile.id,
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final foreign = ProfileScope(
        profileId: 'foreign',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      final initial = <String, String>{
        scope.preferenceKey('playback_state_v1'): history(
          season: 3,
          episode: 4,
        ),
        foreign.preferenceKey('playback_state_v1'): history(
          season: 8,
          episode: 9,
        ),
        'playback_state_v1': history(season: 6, episode: 7),
      };
      SharedPreferences.setMockInitialValues(initial);
      final container = ProviderContainer.test();
      final repository = container.read(
        homeSeriesResumeRepositoryProvider(ProfileSessionMemory.captureOwner()),
      );
      final result = await ProfileRuntime.withCapturedScope(
        foreign,
        () => repository.local(show, 'tt123', isCurrent: () => true),
      );
      expect(result, (
        season: 3,
        episode: 4,
        pct: 25.0,
        tsMs: 1000,
        finished: false,
      ));
      final prefs = await SharedPreferences.getInstance();
      for (final entry in initial.entries) {
        expect(prefs.getString(entry.key), entry.value);
      }
    },
  );

  for (final outcome in ['active', 'profile', 'view']) {
    test('actual Trakt cached-selection transport: $outcome', () async {
      await StorageService.setTraktAccessToken('fixture-token');
      final container = ProviderContainer.test();
      final repository = container.read(
        homeSeriesResumeRepositoryProvider(ProfileSessionMemory.captureOwner()),
      );
      await container.pump();
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      var requests = 0;
      var current = true;
      final client = MockClient((request) {
        expect(request.url.path, '/sync/playback/episodes');
        expect(request.url.queryParameters['page'], '1');
        requests++;
        entered.complete();
        return response.future;
      });
      await http.runWithClient(() async {
        final operation = repository.traktSelection(
          show,
          cached: const TraktContinueWatchingItem(
            meta: show,
            traktContentType: 'episodes',
            season: 2,
            episode: 3,
            progress: 42,
            pausedAtMs: 9876,
          ),
          isCurrent: () => current,
        );
        await entered.future;
        if (outcome == 'profile') ProfileSessionMemory.clearAll();
        if (outcome == 'view') current = false;
        response.complete(
          http.Response(
            jsonEncode([
              {
                'progress': 67,
                'show': {
                  'ids': {'imdb': 'tt123'},
                },
                'episode': {'season': 2, 'number': 3},
              },
            ]),
            200,
            headers: {'x-pagination-page-count': '1'},
          ),
        );
        final result = await operation;
        if (outcome == 'active') {
          expect(result!.tsMs, 9876);
          expect((result.sel.season, result.sel.episode), (2, 3));
          expect(result.sel.traktProgressPercent, 67);
          expect(result.sel.traktSource, true);
        } else {
          expect(result, isNull);
        }
        expect(requests, 1);
      }, () => client);
    });
  }
}
