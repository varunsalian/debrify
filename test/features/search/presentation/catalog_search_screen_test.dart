import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/torrent_search_storage.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  late MockClient client;
  late Map<String, Completer<http.Response>> pending;
  late List<String> requests;
  late List<String> browseRequests;
  late bool serveHome;

  setUp(() {
    disableRuntimeFonts();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    MainPageBridge.setActiveTab('search');
    StremioService.instance.invalidateCache();
    final addon = StremioAddon(
      id: 'search-test',
      name: 'Search test',
      baseUrl: 'https://catalog-search.invalid',
      manifestUrl: 'https://catalog-search.invalid/manifest.json',
      resources: ['catalog'],
      catalogs: [
        for (final name in ['Slow', 'Fast'])
          StremioAddonCatalog(
            id: name.toLowerCase(),
            type: 'movie',
            name: name,
            extraSupported: const ['search'],
          ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([addon.toJson()]),
      'home_hero_trailer_enabled': false,
    });
    pending = {};
    requests = [];
    browseRequests = [];
    serveHome = false;
    client = MockClient((request) async {
      if (serveHome &&
          request.url.host == 'catalog-search.invalid' &&
          !request.url.path.contains('search=')) {
        browseRequests.add(request.url.path);
        return http.Response(
          jsonEncode({
            'metas': [
              {
                'id': 'home-${request.url.path}',
                'type': 'movie',
                'name': 'Home title',
              },
            ],
          }),
          200,
        );
      }
      if (request.url.host != 'catalog-search.invalid' ||
          !request.url.path.contains('search=')) {
        return http.Response('{}', 404);
      }
      final path = Uri.decodeComponent(request.url.path);
      requests.add(path);
      return (pending[path] ??= Completer<http.Response>()).future;
    });
  });

  tearDown(() {
    for (final request in pending.values) {
      if (!request.isCompleted) request.complete(http.Response('{}', 200));
    }
    client.close();
    MainPageBridge.setActiveTab(null);
    StremioService.instance.invalidateCache();
    ProfileRuntime.debugReset();
  });

  Future<void> drive(
    WidgetTester tester,
    FutureOr<void> Function() action,
  ) async {
    await tester.runAsync(
      () => http.runWithClient(() async {
        await action();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }, () => client),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> mount(
    WidgetTester tester,
    bool television, {
    bool searchMode = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await drive(tester, () async {
      await StremioService.instance.getCatalogAddons();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SearchScreen(
              searchMode: searchMode,
              isTelevision: television,
            ),
          ),
        ),
      );
    });
    await drive(tester, () {});
  }

  Future<void> submit(WidgetTester tester, String query) => drive(tester, () {
    final field = tester.widget<TvTextField>(find.byType(TvTextField).first);
    field.controller.text = query;
    field.onSubmitted!(query);
  });

  Future<void> complete(WidgetTester tester, String catalog, String query) =>
      drive(tester, () {
        pending['/catalog/movie/$catalog/search=$query.json']!.complete(
          http.Response(
            jsonEncode({
              'metas': [
                {
                  'id': 'catalog-$catalog',
                  'type': 'movie',
                  'name': '$query $catalog',
                },
              ],
            }),
            200,
          ),
        );
      });

  for (final television in [false, true]) {
    testWidgets('catalog publication preserves TV batching: $television', (
      tester,
    ) async {
      await mount(tester, television);
      await submit(tester, 'Result');
      expect(requests, hasLength(2));
      await complete(tester, 'fast', 'Result');
      expect(
        find.text('Fast Movies'),
        television ? findsNothing : findsOneWidget,
      );
      expect(find.text('Slow Movies'), findsNothing);
      await complete(tester, 'slow', 'Result');
      expect(find.text('Slow Movies'), findsOneWidget);
      expect(find.text('Fast Movies'), findsOneWidget);
      final slow = tester.getTopLeft(find.text('Slow Movies')).dy;
      final fast = tester.getTopLeft(find.text('Fast Movies')).dy;
      expect(television ? slow < fast : fast < slow, isTrue);
      expect(requests, hasLength(2));
      expect(tester.takeException(), isNull);
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
    });
  }

  testWidgets('old catalog completion cannot replace a newer query', (
    tester,
  ) async {
    await mount(tester, false);
    await submit(tester, 'Old');
    await submit(tester, 'New');
    await complete(tester, 'fast', 'Old');
    await complete(tester, 'slow', 'Old');
    expect(find.text('Fast Movies'), findsNothing);
    expect(find.text('Slow Movies'), findsNothing);
    await complete(tester, 'fast', 'New');
    expect(find.text('Fast Movies'), findsOneWidget);
    await complete(tester, 'slow', 'New');
    expect(find.text('Slow Movies'), findsOneWidget);
    expect(requests, hasLength(4));
    expect(tester.takeException(), isNull);
    await drive(tester, () => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('clearing the query rejects late catalog rows', (tester) async {
    await mount(tester, false);
    await submit(tester, 'Old');
    await drive(
      tester,
      () => tester.enterText(find.byType(TextField).first, ''),
    );
    await complete(tester, 'fast', 'Old');
    await complete(tester, 'slow', 'Old');
    expect(find.text('Fast Movies'), findsNothing);
    expect(find.text('Slow Movies'), findsNothing);
    expect(find.text('No catalog matches'), findsNothing);
    expect(tester.takeException(), isNull);
    await drive(tester, () => tester.pumpWidget(const SizedBox()));
  });
  testWidgets(
    'Sources saves disabled addons and reruns the active query on Done',
    (tester) async {
      await mount(tester, false);
      await drive(tester, () => tester.tap(find.text('Sources')));
      await tester.pumpAndSettle();
      // A field action already dispatched while Sources opens may complete
      // under the dialog; closing must requery with the new settings.
      await submit(tester, 'Result');
      await complete(tester, 'fast', 'Result');
      await complete(tester, 'slow', 'Result');
      await drive(tester, () => tester.tap(find.text('Disable all')));
      expect(await TorrentSearchStorage.getCatalogSearchDisabledAddons(), {
        'search-test',
      });
      await drive(tester, () => tester.tap(find.text('Done')));
      await tester.pumpAndSettle();
      expect(find.text('No catalog matches'), findsOneWidget);
      expect(find.text('Fast Movies'), findsNothing);
      expect(requests, hasLength(2));
      await drive(tester, () => tester.pumpWidget(const SizedBox()));
    },
  );

  testWidgets('total failure remains distinguishable from no catalog matches', (
    tester,
  ) async {
    await mount(tester, true);
    await submit(tester, 'Result');
    await drive(tester, () {
      for (final response in pending.values) {
        response.complete(http.Response('{}', 503));
      }
    });
    expect(find.text('No catalog matches'), findsOneWidget);
    expect(find.textContaining("2 sources didn't respond"), findsOneWidget);
    expect(requests, hasLength(2));
    await drive(tester, () => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('outgoing profile clears catalog rows before route disposal', (
    tester,
  ) async {
    await mount(tester, false);
    await submit(tester, 'Result');
    await complete(tester, 'fast', 'Result');
    expect(find.text('Fast Movies'), findsOneWidget);
    await drive(
      tester,
      () => ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'incoming', dataGeneration: 1, sessionEpoch: 2),
      ),
    );
    expect(find.text('Fast Movies'), findsNothing);
    await complete(tester, 'slow', 'Result');
    expect(find.text('Slow Movies'), findsNothing);
    expect(tester.takeException(), isNull);
    await drive(tester, () => tester.pumpWidget(const SizedBox()));
  });
  testWidgets('clearing restores Home through a deferred settings reload', (
    tester,
  ) async {
    serveHome = true;
    MainPageBridge.setActiveTab('home');
    StorageService.tvHomeStyleCached = 'classic';
    await mount(tester, false, searchMode: false);
    expect(find.text('Slow Movies'), findsOneWidget);
    expect(find.text('Fast Movies'), findsOneWidget);
    final initialRequests = browseRequests.length;
    await submit(tester, 'Result');
    await complete(tester, 'fast', 'Result');
    await complete(tester, 'slow', 'Result');
    await drive(tester, () async {
      await StorageService.setHomeDisabledSections({'search-test:movie:fast'});
      MainPageBridge.notifyHomeSettingsChanged();
    });
    expect(browseRequests.length, initialRequests);
    expect(find.text('Fast Movies'), findsOneWidget);
    await drive(
      tester,
      () => tester.enterText(find.byType(TextField).first, ''),
    );
    await drive(tester, () {});
    expect(find.text('Slow Movies'), findsOneWidget);
    expect(find.text('Fast Movies'), findsNothing);
    // The deferred reload applies new membership to cached catalog contents;
    // it must not restore the old two-row board or issue redundant fetches.
    expect(browseRequests.length, initialRequests);
    expect(tester.takeException(), isNull);
    await drive(tester, () => tester.pumpWidget(const SizedBox()));
  });
}
