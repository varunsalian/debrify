import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/search/data/stremio_catalog_search_repository.dart';
import 'package:debrify/features/search/presentation/catalog_search_projection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/watched_status_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const key = 'catalog_search_disabled_addons_v1';
const catalog = StremioAddonCatalog(
  id: 'movies',
  type: 'movie',
  name: 'Popular',
  extraSupported: ['search'],
);
final addon = StremioAddon(
  id: 'fixture',
  name: 'Fixture',
  baseUrl: 'https://fixture.invalid',
  manifestUrl: 'https://fixture.invalid/manifest.json',
  catalogs: [catalog],
);
final origin = ProfileScope(
  profileId: 'origin',
  dataGeneration: 1,
  sessionEpoch: 1,
);
final incoming = ProfileScope(
  profileId: 'incoming',
  dataGeneration: 1,
  sessionEpoch: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StremioCatalogSearchRepository repository;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    HideWatchedPrefs.debugReset();
    StremioService.instance.invalidateCache();
    repository = StremioCatalogSearchRepository(
      owner: ProfileSessionMemory.captureOwner(),
      service: StremioService.instance,
    );
  });
  tearDown(() {
    StremioService.instance.invalidateCache();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    HideWatchedPrefs.debugReset();
  });

  test(
    'raw cursor, query and addon survive into the legacy See All projection',
    () async {
      final requests = <Uri>[];
      final row = await http.runWithClient(
        () => repository.searchCatalog(addon, catalog, 'two words'),
        () => MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'metas': [
                {'id': 'catalog-1', 'type': 'movie', 'name': 'One'},
                {'id': '', 'type': 'movie', 'name': 'Invalid'},
                {'id': 'catalog-2', 'type': 'movie', 'name': 'Two'},
              ],
            }),
            200,
          );
        }),
      );
      expect(requests, hasLength(1));
      expect(
        Uri.decodeComponent(requests.single.path),
        contains('search=two words'),
      );
      expect(row!.items.length, 2);
      expect(row.nextSkip, 3);
      expect(row.items.first.sourceAddon?.id, addon.id);
      final projection = catalogSearchSection(row);
      expect(projection.query, 'two words');
      expect(projection.nextSkip, 3);
      expect(projection.title, 'Popular Movies');
      projection.items.clear();
      projection.nextSkip = 100;
      expect(row.items.length, 2);
      expect(row.nextSkip, 3);
    },
  );

  test(
    'empty response omits the row and transport failure stays distinguishable',
    () async {
      expect(
        await http.runWithClient(
          () => repository.searchCatalog(addon, catalog, 'none'),
          () => MockClient((_) async => http.Response('{"metas":[]}', 200)),
        ),
        isNull,
      );
      await expectLater(
        http.runWithClient(
          () => repository.searchCatalog(addon, catalog, 'failed'),
          () => MockClient((_) async => http.Response('{}', 503)),
        ),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test('profile switch rejects late metadata and further requests', () async {
    final pending = Completer<http.Response>();
    var requests = 0;
    final result = http.runWithClient(
      () => repository.searchCatalog(addon, catalog, 'movies'),
      () => MockClient((_) {
        requests++;
        return pending.future;
      }),
    );
    await Future<void>.delayed(Duration.zero);
    ProfileRuntime.initializeCommitted(incoming);
    pending.complete(
      http.Response(
        '{"metas":[{"id":"catalog-1","type":"movie","name":"One"}]}',
        200,
      ),
    );
    expect(await result, isNull);
    expect(await repository.searchCatalog(addon, catalog, 'next'), isNull);
    expect(requests, 1);
  });

  test(
    'legacy writes retain exact storage format and snapshot input',
    () async {
      final disabled = {'one'};
      final saving = repository.writeDisabledAddons(disabled);
      disabled.add('two');
      await saving;
      expect(await StorageService.getCatalogSearchDisabledAddons(), {'one'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), '["one"]');
      await repository.writeDisabledAddons({});
      expect(prefs.containsKey(key), isFalse);
    },
  );

  test('settings never write into the incoming profile', () async {
    ProfileRuntime.initializeCommitted(origin);
    repository = StremioCatalogSearchRepository(
      owner: ProfileSessionMemory.captureOwner(),
      service: StremioService.instance,
    );
    await repository.writeDisabledAddons({'origin-source'});
    ProfileRuntime.publish(incoming);
    await repository.writeDisabledAddons({'late-source'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(origin.preferenceKey(key)), '["origin-source"]');
    expect(prefs.containsKey(incoming.preferenceKey(key)), isFalse);
  });

  test(
    'profile handoff during a settings barrier cannot recreate deleted data',
    () async {
      ProfileRuntime.initializeCommitted(origin);
      repository = StremioCatalogSearchRepository(
        owner: ProfileSessionMemory.captureOwner(),
        service: StremioService.instance,
      );
      final release = Completer<void>();
      final entered = Completer<void>();
      final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final writing = repository.writeDisabledAddons({'outgoing'});
      // Attach the expected failure handler before releasing the pending write.
      final rejected = expectLater(writing, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      ProfileRuntime.publish(incoming);
      release.complete();
      await barrier;
      await rejected;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(origin.preferenceKey(key)), isFalse);
      expect(prefs.containsKey(incoming.preferenceKey(key)), isFalse);
    },
  );
  test(
    'watched filtering is single-shot and retains raw cursor before filtering',
    () async {
      SharedPreferences.setMockInitialValues({
        HideWatchedPrefs.key: true,
        'finished_movies_v1': ['tt1'],
      });
      await HideWatchedPrefs.warmUp();
      WatchedStatusService.instance.resetProfileScope();
      WatchedStatusService.instance.ensureStarted();
      await WatchedStatusService.instance.firstSnapshot;
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response(
          jsonEncode({
            'metas': [
              {'id': 'tt1', 'type': 'movie', 'name': 'Watched'},
              if (requests == 1) {'id': 'tt2', 'type': 'movie', 'name': 'New'},
            ],
          }),
          200,
        );
      });
      final row = await http.runWithClient(
        () => repository.searchCatalog(addon, catalog, 'movies'),
        () => client,
      );
      expect(row!.items.map((item) => item.id), ['tt2']);
      expect(row.nextSkip, 2);
      expect(requests, 1);
      final empty = await http.runWithClient(
        () => repository.searchCatalog(addon, catalog, 'watched only'),
        () => client,
      );
      expect(empty, isNull);
      expect(requests, 2); // No watched-only top-up requests.
      WatchedStatusService.instance.resetProfileScope();
    },
  );
}
