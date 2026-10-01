import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/home/application/home_detail_providers.dart';
import 'package:debrify/features/home/models/home_catalog_origin.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

StremioAddon source(String id) => StremioAddon(
  id: id,
  name: id,
  baseUrl: 'https://origin.invalid',
  manifestUrl: 'https://origin.invalid/manifest.json',
  resources: ['meta'],
  addedAt: DateTime.utc(2026),
);
String key(StremioAddon addon, StremioMeta item) =>
    'catalog_progress_identity_v1:${addon.portableConfigurationKey}:${item.id}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    StremioService.instance.invalidateCache();
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'retired mapping queued at the real preference barrier cannot persist or publish cache revision',
    () async {
      final container = ProviderContainer.test();
      final repository = container.read(
        homeCatalogOriginRepositoryProvider(
          ProfileSessionMemory.captureOwner(),
        ),
      );
      final addon = source('com.linvo.cinemeta');
      const item = StremioMeta(id: 'tt97001', type: 'series', name: 'Fixture');
      final entered = Completer<void>(), release = Completer<void>();
      final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final revision = StremioService.instance.catalogProgressRevision.value;
      var checks = 0;
      final operation = repository.prepare(
        item,
        addon,
        isCurrent: () {
          checks++;
          return true;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(checks, greaterThanOrEqualTo(3));
      ProfileSessionMemory.clearAll();
      release.complete();
      await snapshot;
      expect((await operation).status, HomeCatalogOriginStatus.retired);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key(addon, item)), isNull);
      expect(StremioService.instance.catalogProgressRevision.value, revision);
    },
  );

  test(
    'active mapping persists only in the originating committed profile',
    () async {
      ProfileRuntime.debugReset();
      final scope = ProfileScope(
        profileId: 'catalog-origin',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      final container = ProviderContainer.test();
      final repository = container.read(
        homeCatalogOriginRepositoryProvider(
          ProfileSessionMemory.captureOwner(),
        ),
      );
      final addon = source('com.linvo.cinemeta');
      const item = StremioMeta(id: 'tt97002', type: 'series', name: 'Fixture');
      final result = await repository.prepare(
        item,
        addon,
        isCurrent: () => true,
      );
      expect(result.status, HomeCatalogOriginStatus.ready);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(scope.preferenceKey(key(addon, item))), item.id);
      expect(prefs.getString(key(addon, item)), isNull);
    },
  );

  test(
    'retirement during actual metadata fetch skips progress mapping and local inventory',
    () async {
      final container = ProviderContainer.test();
      final repository = container.read(
        homeCatalogOriginRepositoryProvider(
          ProfileSessionMemory.captureOwner(),
        ),
      );
      final addon = source('custom-provider');
      const item = StremioMeta(
        id: 'custom-cut',
        imdbId: 'tt97003',
        type: 'series',
        name: 'Custom',
      );
      final entered = Completer<void>(), response = Completer<http.Response>();
      final client = MockClient((_) {
        entered.complete();
        return response.future;
      });
      final revision = StremioService.instance.catalogProgressRevision.value;
      var current = true;
      final operation = http.runWithClient(
        () => repository.prepare(item, addon, isCurrent: () => current),
        () => client,
      );
      await entered.future;
      current = false;
      response.complete(
        http.Response(
          jsonEncode({
            'meta': {
              'videos': [
                {'id': 'cut:1', 'season': 1, 'number': 1},
              ],
            },
          }),
          200,
        ),
      );
      expect((await operation).status, HomeCatalogOriginStatus.retired);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key(addon, item)), isNull);
      expect(
        prefs.getString(StorageService.localSeriesCompletionStateKey),
        isNull,
      );
      expect(StremioService.instance.catalogProgressRevision.value, revision);
    },
  );
}
