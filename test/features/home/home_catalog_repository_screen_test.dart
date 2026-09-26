import 'dart:async';

import 'package:debrify/features/home/application/home_catalog_dependencies.dart';
import 'package:debrify/features/home/data/home_catalog_repository.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/features/home/models/home_catalog_state.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class CatalogObserver extends ProviderObserver {
  final updates = <HomeCatalogState>[];

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (newValue is HomeCatalogState) updates.add(newValue);
  }
}

void main() {
  testWidgets('Home uses injected catalog access and retires pending rows', (
    tester,
  ) async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    PlatformUtil.debugSetAndroidTvCached(false);
    PlatformUtil.debugSetTvOS(false);
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': '[]',
      'tv_home_style': 'classic',
      'home_hero_source_v1': '{"mode":"auto","ids":[]}',
    });
    StorageService.tvHomeStyleCached = 'classic';
    StremioService.instance.invalidateCache();
    addTearDown(() {
      PlatformUtil.debugSetAndroidTvCached(null);
      PlatformUtil.debugSetTvOS(null);
      ProfileRuntime.debugReset();
    });
    final started = Completer<void>();
    final response = Completer<List<StremioMeta>>();
    final catalog = StremioAddonCatalog(
      id: 'popular',
      type: 'movie',
      name: 'Popular',
    );
    final addon = StremioAddon(
      id: 'fixture',
      name: 'Fixture',
      manifestUrl: 'https://fixture.invalid/manifest.json',
      baseUrl: 'https://fixture.invalid',
      addedAt: DateTime.utc(2026),
      catalogs: [catalog],
    );
    var reads = 0;
    final requests = <(StremioAddon, StremioAddonCatalog, int)>[];
    final repository = HomeCatalogRepository(
      readAddons: () async {
        reads++;
        return [addon];
      },
      readHides: () => null,
      fetchPage: (source, row, skip, raw) {
        requests.add((source, row, skip));
        raw(1);
        started.complete();
        return response.future;
      },
    );
    final observer = CatalogObserver();
    final client = MockClient((_) async => http.Response('[]', 200));
    await tester.runAsync(
      () => http.runWithClient(() async {
        await tester.pumpWidget(
          ProviderScope(
            observers: [observer],
            overrides: [
              homeCatalogRepositoryProvider.overrideWithValue(repository),
            ],
            child: const MaterialApp(home: SearchScreen(isTelevision: true)),
          ),
        );
      }, () => client),
    );
    for (var attempt = 0; !started.isCompleted && attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(started.isCompleted, isTrue);
    expect(reads, 1);
    expect(requests, [(addon, catalog, 0)]);
    expect(observer.updates.last.references, [(addon, catalog)]);
    expect(observer.updates.last.cursor, 1);
    expect(observer.updates.last.committed, isNull);
    final updatesBeforeDisposal = observer.updates.length;
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      response.complete([
        StremioMeta(id: 'late', type: 'movie', name: 'Late result'),
      ]);
      await response.future;
      // Drain the batch and its caller's continuations after removing the scope.
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 1);
    expect(requests, [(addon, catalog, 0)]);
    expect(observer.updates, hasLength(updatesBeforeDisposal));
    expect(tester.takeException(), isNull);
  });
}
