import 'package:debrify/services/mdblist/mdblist_discover_models.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/see_all/catalog_see_all_screen.dart';
import 'package:debrify/screens/see_all/mdblist_see_all_screen.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/mdblist/mdblist_discover_source.dart';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/watched_status_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/see_all/see_all_poster_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child) => MaterialApp(
  home: AppThemeScope(theme: AppThemes.legacy, child: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      HideWatchedPrefs.key: true,
      'finished_movies_v1': [for (var i = 0; i < 50; i++) 'tt$i'],
    });
    HideWatchedPrefs.debugReset();
    await HideWatchedPrefs.warmUp();
    WatchedStatusService.instance.resetProfileScope();
    WatchedStatusService.instance.ensureStarted();
    await WatchedStatusService.instance.firstSnapshot;
  });

  tearDown(() => HideWatchedPrefs.debugReset());

  for (final seeded in [false, true]) {
    testWidgets(
      'See All resumes watched-only ${seeded ? "later" : "initial"} pages',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const catalog = StremioAddonCatalog(
          id: 'test',
          type: 'movie',
          name: 'Test',
        );
        final addon = StremioAddon(
          id: 'test',
          name: 'Test',
          manifestUrl: 'https://example.invalid/manifest.json',
          baseUrl: 'https://example.invalid',
          catalogs: [catalog],
        );
        final skips = <int>[];
        await tester.pumpWidget(
          host(
            CatalogSeeAllScreen(
              isTelevision: seeded,
              addon: addon,
              initialCatalog: catalog,
              onOpenItem: (_) {},
              seedItems: seeded
                  ? [StremioMeta(id: 'seed', type: 'movie', name: 'Seed')]
                  : [],
              seedNextSkip: seeded ? 10 : 0,
              fetchPage: (skip, raw) async {
                skips.add(skip);
                raw(skip < 60 ? 10 : 0);
                return [
                  if (skip < 60)
                    for (var i = skip; i < skip + 10; i++)
                      StremioMeta(
                        id: 'tt$i',
                        imdbId: 'tt$i',
                        type: 'movie',
                        name: 'Title $i',
                      ),
                ];
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(skips, seeded ? [10, 20, 30, 40] : [0, 10, 20, 30]);
        expect(find.text('Continue loading'), findsOneWidget);
        final countBefore = skips.length;
        await tester.pump(const Duration(seconds: 2));
        expect(skips.length, countBefore); // No unbounded automatic retry.
        if (seeded) {
          final state = tester.state<SeeAllPosterGridState>(
            find.byType(SeeAllPosterGrid),
          );
          state.focusFirst();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'seeall_retry',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text('Continue loading'));
        }
        await tester.pumpAndSettle();
        expect(
          skips,
          seeded ? [10, 20, 30, 40, 50, 60] : [0, 10, 20, 30, 40, 50, 60],
        );
        final grid = tester.widget<SeeAllPosterGrid>(
          find.byType(SeeAllPosterGrid),
        );
        expect(grid.items.any((m) => m.id == 'tt50'), isTrue);
        expect(grid.items.any((m) => m.id == 'tt0'), isFalse);
      },
    );
  }

  for (final public in [false, true]) {
    for (final liked in [false, true]) {
      testWidgets('MDBList initial list public=$public liked=$liked', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final service = MdblistService.forTesting(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'movies': [
                  {
                    'imdb_id': 'tt1',
                    'title': 'Watched title',
                    'mediatype': 'movie',
                  },
                  {
                    'imdb_id': 'tt99',
                    'title': 'New title',
                    'mediatype': 'movie',
                  },
                ],
              }),
              200,
            ),
          ),
          apiKeyProvider: () async => 'test-key',
        );
        await tester.pumpWidget(
          host(
            MdblistSeeAllScreen(
              initialList: MdblistListChoice(
                id: 1,
                name: 'A list',
                liked: liked,
              ),
              initialListIsPublic: public,
              source: MdblistDiscoverSource.forTesting(service),
              isAuthenticated: () async => true,
              onOpen: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final grid = tester.widget<SeeAllPosterGrid>(
          find.byType(SeeAllPosterGrid),
        );
        expect(grid.items.any((m) => m.id == 'tt1'), !public || liked);
        expect(grid.items.any((m) => m.id == 'tt99'), isTrue);
      });
    }
  }
  testWidgets(
    'watched recommendation pages remain resumable with the TV remote',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = <String>[];
      final service = MdblistService.forTesting(
        client: MockClient((request) async {
          requests.add(request.url.toString());
          if (request.url.path == '/lists/recommended') {
            return http.Response(
              jsonEncode({
                'sections': [
                  {'section': 'rising', 'name': 'Rising'},
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/lists/recommended/rising/items') {
            final second = request.url.queryParameters['cursor'] == 'next';
            return http.Response(
              jsonEncode({
                'movies': [
                  {
                    'imdb_id': second ? 'tt99' : 'tt1',
                    'title': second ? 'Unseen next page' : 'Watched first page',
                    'mediatype': 'movie',
                  },
                ],
                'pagination': {'next_cursor': second ? null : 'next'},
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'movies': []}), 200);
        }),
        apiKeyProvider: () async => 'test-key',
      );
      await tester.pumpWidget(
        host(
          MdblistSeeAllScreen(
            source: MdblistDiscoverSource.forTesting(service),
            isAuthenticated: () async => true,
            isTelevision: true,
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(StremioDropdown<MdblistDiscoverGroup>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('For You').last);
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches these filters'), findsOneWidget);
      expect(requests.where((r) => r.contains('/rising/items')), hasLength(1));
      expect(find.text('Continue loading'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'msa_more');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.contains('/rising/items')), hasLength(2));
      expect(requests.last, contains('cursor=next'));
      final grid = tester.widget<SeeAllPosterGrid>(
        find.byType(SeeAllPosterGrid),
      );
      expect(grid.items.map((m) => m.id), ['tt99']);
      expect(find.text('Continue loading'), findsNothing);
    },
  );
}
