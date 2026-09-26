import 'dart:async';
import 'dart:convert';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:debrify/features/sources/data/stored_saved_sources_repository.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pin = SeriesSource(
  torrentHash: 'custom',
  torrentName: 'Edit',
  debridService: 'rd',
  debridTorrentId: '1',
  boundAt: 1,
  addonCatalogId: 'OnePace',
  addonCatalogKey: 'config-a',
);
const canonicalPin = SeriesSource(
  torrentHash: 'canonical',
  torrentName: 'Original',
  debridService: 'rd',
  debridTorrentId: '2',
  boundAt: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final custom = const CustomSeriesIdentity('config-a', 'OnePace').id;
  const canonical = 'tt0388629';
  late ProfileScope first;
  late ProfileScope second;
  late ProfileRegistry registry;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    ProfileRuntime.debugReset();
    SharedPreferences.setMockInitialValues({});
    registry = await ProfileRegistry.open(path: inMemoryDatabasePath);
    final original = await registry.createProfile(
      name: 'First',
      role: UserProfileRole.admin,
    );
    final incoming = await registry.createProfile(
      name: 'Second',
      role: UserProfileRole.admin,
    );
    first = ProfileScope(
      profileId: original.id,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    second = ProfileScope(
      profileId: incoming.id,
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 1)),
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(first);
    StremioService.instance.invalidateCache();
    WebDavSyncTombstoneRecorder.debugInstall(sink: (_, _) {});
  });
  tearDown(() async {
    StremioService.instance.invalidateCache();
    WebDavSyncTombstoneRecorder.debugReset();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
  });

  StoredSavedSourcesRepository repository({
    bool customSelection = false,
    bool series = true,
  }) => StoredSavedSourcesRepository(
    SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: AdvancedSearchSelection(
        imdbId: customSelection ? custom : canonical,
        title: 'Fixture',
        isSeries: series,
        stremioAddonKey: customSelection ? 'config-a' : null,
        stremioCatalogId: customSelection ? 'OnePace' : null,
      ),
    ),
  );

  test(
    'legacy single-object pin migrates to a list under its original profile',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        first.preferenceKey('series_source_$canonical'),
        jsonEncode(canonicalPin.toJson()),
      );
      final loaded = await repository().load();
      expect(loaded.sources.single.bindingKey, canonicalPin.bindingKey);
      expect(
        jsonDecode(
          prefs.getString(first.preferenceKey('series_source_$canonical'))!,
        ),
        isA<List>(),
      );
      expect(
        prefs.getString(second.preferenceKey('series_source_$canonical')),
        isNull,
      );
      expect(() => loaded.sources.clear(), throwsUnsupportedError);
    },
  );

  test(
    'custom migration preserves pin scope, order, cleanup and origin tombstone',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        first.preferenceKey('series_source_$canonical'),
        jsonEncode([canonicalPin.toJson(), pin.toJson()]),
      );
      final recorded = <String>[];
      WebDavSyncTombstoneRecorder.debugInstall(
        sink: (profile, keys) {
          recorded.add(profile);
        },
      );
      final loaded = await repository(customSelection: true).load();
      expect(loaded.sources.single.bindingKey, pin.bindingKey);
      final remaining =
          jsonDecode(
                prefs.getString(
                  first.preferenceKey('series_source_$canonical'),
                )!,
              )
              as List;
      expect(remaining.single['torrentHash'], canonicalPin.torrentHash);
      expect(recorded, [first.profileId]);
      expect(
        prefs.getString(second.preferenceKey('series_source_$custom')),
        isNull,
      );
    },
  );

  for (final customSelection in [false, true]) {
    for (final retirement in ['switch', 'clear']) {
      test(
        'queued migration cannot recreate deleted data: custom=$customSelection retirement=$retirement',
        () async {
          final prefs = await SharedPreferences.getInstance();
          final key = first.preferenceKey('series_source_$canonical');
          await prefs.setString(
            key,
            jsonEncode(
              customSelection ? [pin.toJson()] : canonicalPin.toJson(),
            ),
          );
          final repo = repository(customSelection: customSelection);
          final entered = Completer<void>();
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          final snapshot = ProfilePreferences.captureMutationSnapshot((
            _,
          ) async {
            entered.complete();
            await release.future;
          });
          await entered.future;
          var finished = false;
          final load = repo
              .load()
              .then<Object?>((value) => value, onError: (Object error) => error)
              .whenComplete(() => finished = true);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(finished, isFalse);
          if (retirement == 'switch') {
            ProfileRuntime.publish(second);
          } else {
            ProfileSessionMemory.clearAll();
          }
          await prefs.remove(key);
          release.complete();
          await snapshot;
          await load;
          expect(
            prefs.getKeys().where((key) => key.contains('series_source_')),
            isEmpty,
          );
        },
      );
    }
  }

  test(
    'retirement during cleanup never removes incoming or remaining origin pins',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final original = jsonEncode([canonicalPin.toJson(), pin.toJson()]);
      await prefs.setString(
        first.preferenceKey('series_source_$canonical'),
        original,
      );
      await prefs.setString(
        second.preferenceKey('series_source_$canonical'),
        original,
      );
      final recorded = <String>[];
      WebDavSyncTombstoneRecorder.debugInstall(
        sink: (profile, keys) {
          recorded.add(profile);
          ProfileRuntime.publish(second);
        },
      );
      await expectLater(
        repository(customSelection: true).load(),
        throwsStateError,
      );
      expect(recorded, [first.profileId]);
      expect(
        prefs.getString(first.preferenceKey('series_source_$canonical')),
        original,
      );
      expect(
        prefs.getString(second.preferenceKey('series_source_$canonical')),
        original,
      );
      expect(
        prefs.getString(second.preferenceKey('series_source_$custom')),
        isNull,
      );
    },
  );
  test(
    'explicit unpin removes only the selected binding and records origin tombstone',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final original = jsonEncode([canonicalPin.toJson(), pin.toJson()]);
      await prefs.setString(
        first.preferenceKey('series_source_$canonical'),
        original,
      );
      await prefs.setString(
        second.preferenceKey('series_source_$canonical'),
        original,
      );
      final recorded = <String>[];
      WebDavSyncTombstoneRecorder.debugInstall(
        sink: (profile, keys) => recorded.add(profile),
      );
      final repo = repository();
      expect(await repo.remove(canonicalPin), isTrue);
      final remaining =
          jsonDecode(
                prefs.getString(
                  first.preferenceKey('series_source_$canonical'),
                )!,
              )
              as List;
      expect(remaining.single['torrentHash'], pin.torrentHash);
      expect(recorded, [first.profileId]);
      expect(
        prefs.getString(second.preferenceKey('series_source_$canonical')),
        original,
      );
      expect(await repo.remove(pin), isTrue);
      expect(
        prefs.getString(first.preferenceKey('series_source_$canonical')),
        isNull,
      );
    },
  );

  for (final retirement in ['switch', 'clear']) {
    test(
      'queued unpin cannot recreate deleted data after $retirement',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final original = jsonEncode([canonicalPin.toJson(), pin.toJson()]);
        final key = first.preferenceKey('series_source_$canonical');
        final incomingKey = second.preferenceKey('series_source_$canonical');
        await prefs.setString(key, original);
        await prefs.setString(incomingKey, original);
        final repo = repository();
        final entered = Completer<void>();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        var finished = false;
        final removal = repo
            .remove(canonicalPin)
            .whenComplete(() => finished = true);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(finished, isFalse);
        if (retirement == 'switch') {
          ProfileRuntime.publish(second);
        } else {
          ProfileSessionMemory.clearAll();
        }
        await prefs.remove(key);
        release.complete();
        await snapshot;
        expect(await removal, isFalse);
        expect(prefs.getString(key), isNull);
        expect(prefs.getString(incomingKey), original);
        expect(await repo.remove(pin), isFalse);
      },
    );
  }
  for (final series in [false, true]) {
    test(
      'save preserves ${series ? 'series append/dedupe' : 'movie replacement'} policy',
      () async {
        final repo = repository(series: series);
        expect(await repo.save(canonicalPin), isTrue);
        expect(await repo.save(pin), isTrue);
        expect(await repo.save(canonicalPin), isTrue);
        final prefs = await SharedPreferences.getInstance();
        final rows =
            jsonDecode(
                  prefs.getString(
                    first.preferenceKey('series_source_$canonical'),
                  )!,
                )
                as List;
        expect(
          rows.map((row) => row['torrentHash']),
          series
              ? [canonicalPin.torrentHash, pin.torrentHash]
              : [canonicalPin.torrentHash],
        );
        expect(
          prefs.getString(second.preferenceKey('series_source_$canonical')),
          isNull,
        );
      },
    );

    for (final retirement in ['switch', 'clear']) {
      test(
        'queued ${series ? 'series' : 'movie'} save cannot recreate deleted profile data after $retirement',
        () async {
          final prefs = await SharedPreferences.getInstance();
          final key = first.preferenceKey('series_source_$canonical');
          final incomingKey = second.preferenceKey('series_source_$canonical');
          final original = jsonEncode([canonicalPin.toJson()]);
          await prefs.setString(key, original);
          await prefs.setString(incomingKey, original);
          final repo = repository(series: series);
          final entered = Completer<void>();
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          final snapshot = ProfilePreferences.captureMutationSnapshot((
            _,
          ) async {
            entered.complete();
            await release.future;
          });
          await entered.future;
          var finished = false;
          final save = repo.save(pin).whenComplete(() => finished = true);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(finished, isFalse);
          if (retirement == 'switch') {
            ProfileRuntime.publish(second);
          } else {
            ProfileSessionMemory.clearAll();
          }
          await prefs.remove(key);
          release.complete();
          await snapshot;
          expect(await save, isFalse);
          expect(prefs.getString(key), isNull);
          expect(prefs.getString(incomingKey), original);
          expect(await repo.save(pin), isFalse);
        },
      );
    }
  }

  test(
    'movie replacement rejects retirement after recording origin tombstone',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final original = jsonEncode([canonicalPin.toJson()]);
      final key = first.preferenceKey('series_source_$canonical');
      final incomingKey = second.preferenceKey('series_source_$canonical');
      await prefs.setString(key, original);
      await prefs.setString(incomingKey, original);
      final repo = repository(series: false);
      final recorded = <String>[];
      WebDavSyncTombstoneRecorder.debugInstall(
        sink: (profile, keys) {
          recorded.add(profile);
          ProfileRuntime.publish(second);
        },
      );
      expect(await repo.save(pin), isFalse);
      expect(recorded, [first.profileId]);
      expect(prefs.getString(key), original);
      expect(prefs.getString(incomingKey), original);
    },
  );

  test(
    'save ignores a foreign captured zone and retains the live originating profile',
    () async {
      final repo = repository();
      expect(
        await ProfileRuntime.withCapturedScope(
          second,
          () => repo.save(canonicalPin),
        ),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(first.preferenceKey('series_source_$canonical')),
        isNotNull,
      );
      expect(
        prefs.getString(second.preferenceKey('series_source_$canonical')),
        isNull,
      );
    },
  );
}
