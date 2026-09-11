import 'package:debrify/widgets/collections/tv_collection_titles.dart';
import 'dart:convert';
import 'dart:async';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/services/collection_native_source_service.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/watched_status_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/see_all/see_all_poster_grid.dart';
import 'package:debrify/widgets/collections/collection_list_gallery.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tv_collection_list_style': 'grid',
      HomeCollectionsStore.folderLayoutKey: 'rows',
    });
    StremioService.instance.invalidateCache();
  });

  HomeCollection collection({String? viewMode, bool unknown = false}) =>
      HomeCollection(
        id: 'native',
        title: 'Native collection',
        viewMode: viewMode,
        folders: [
          HomeCollectionFolder(
            id: 'f',
            title: 'Folder',
            sources: [
              CollectionCatalogSource.fromJson({
                'provider': 'tmdb',
                'tmdbSourceType': 'DISCOVER',
                'title': 'New movies',
              })!,
              if (unknown)
                CollectionCatalogSource.fromJson({
                  'provider': 'future',
                  'title': 'Unavailable',
                })!,
            ],
          ),
        ],
      );

  CollectionNativeSourceService service({int status = 200}) =>
      CollectionNativeSourceService(
        tmdbToken: 'dummy',
        resolveIds: false,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'results': [
                {'id': 42, 'title': 'Native movie'},
              ],
              'total_pages': 1,
            }),
            status,
          ),
        ),
      );

  for (final all in [false, true]) {
    testWidgets(
      'late watched filtering automatically reaches unwatched next page (All $all)',
      (tester) async {
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({
            'tv_collection_list_style': 'grid',
            HideWatchedPrefs.key: true,
            'finished_movies_v1': ['tt1234567'],
          });
          HideWatchedPrefs.debugReset();
          await HideWatchedPrefs.warmUp();
          WatchedStatusService.instance.resetProfileScope();
          WatchedStatusService.instance.ensureStarted();
          await WatchedStatusService.instance.firstSnapshot;
        });
        addTearDown(() {
          HideWatchedPrefs.debugReset();
          WatchedStatusService.instance.resetProfileScope();
        });
        final identity = Completer<http.Response>();
        var secondPageRequests = 0;
        final native = CollectionNativeSourceService(
          tmdbToken: 'dummy',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/external_ids')) {
              if (request.url.path.contains('/100/')) {
                return http.Response('{"imdb_id":"tt9999999"}', 200);
              }
              return identity.future;
            }
            final page = int.parse(request.url.queryParameters['page']!);
            if (page == 2) secondPageRequests++;
            return http.Response(
              jsonEncode({
                'results': page == 1
                    ? [
                        for (var id = 1; id <= 40; id++)
                          {'id': id, 'title': 'Watched $id'},
                      ]
                    : [
                        {'id': 100, 'title': 'Unwatched next page'},
                      ],
                'total_pages': 2,
              }),
              200,
            );
          }),
        );
        addTearDown(native.close);
        final base = collection(viewMode: 'TABBED_GRID');
        final sample = HomeCollection(
          id: base.id,
          title: base.title,
          viewMode: base.viewMode,
          folders: [
            base.folders.single.copyWith(
              sources: [
                ...base.folders.single.sources,
                CollectionCatalogSource.fromJson({
                  'provider': 'tmdb',
                  'tmdbSourceType': 'COMPANY',
                  'tmdbId': 420,
                  'title': 'Company',
                })!,
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionFolderScreen(
              collection: sample,
              isTelevision: true,
              nativeSources: native,
              onOpenItem: (_) {},
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        if (all) {
          final list = tester
              .widgetList<StremioDropdown<int>>(
                find.byType(StremioDropdown<int>),
              )
              .firstWhere((d) => d.label == 'List');
          list.onSelected(
            list.options.firstWhere((o) => o.label == 'All').value,
          );
          await tester.pump();
        }
        expect(find.byType(SeeAllPosterGrid), findsOneWidget);
        expect(secondPageRequests, 0);
        identity.complete(http.Response('{"imdb_id":"tt1234567"}', 200));
        await tester.pumpAndSettle();
        expect(secondPageRequests, greaterThan(0));
        expect(find.text('Retry'), findsNothing);
        final grid = tester.widget<SeeAllPosterGrid>(
          find.byType(SeeAllPosterGrid),
        );
        expect(grid.items.map((m) => m.name), ['Unwatched next page']);
        expect(grid.exhausted, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final all in [false, true]) {
    testWidgets(
      'late watched identities show empty state and retain TV navigation (All $all)',
      (tester) async {
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({
            'tv_collection_list_style': 'grid',
            HideWatchedPrefs.key: true,
            'finished_movies_v1': ['tt1234567'],
          });
          HideWatchedPrefs.debugReset();
          await HideWatchedPrefs.warmUp();
          WatchedStatusService.instance.resetProfileScope();
          WatchedStatusService.instance.ensureStarted();
          await WatchedStatusService.instance.firstSnapshot;
        });
        addTearDown(() {
          HideWatchedPrefs.debugReset();
          WatchedStatusService.instance.resetProfileScope();
        });
        final identity = Completer<http.Response>();
        final native = CollectionNativeSourceService(
          tmdbToken: 'dummy',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/external_ids')) {
              return identity.future;
            }
            return http.Response(
              '{"results":[{"id":42,"title":"Film"}],"total_pages":1}',
              200,
            );
          }),
        );
        addTearDown(native.close);
        final base = collection(viewMode: 'TABBED_GRID');
        final sample = HomeCollection(
          id: base.id,
          title: base.title,
          viewMode: base.viewMode,
          folders: [
            base.folders.single.copyWith(
              sources: [
                ...base.folders.single.sources,
                CollectionCatalogSource.fromJson({
                  'provider': 'tmdb',
                  'tmdbSourceType': 'COMPANY',
                  'tmdbId': 420,
                  'title': 'Company',
                })!,
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionFolderScreen(
              collection: sample,
              isTelevision: true,
              nativeSources: native,
              onOpenItem: (_) {},
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        if (all) {
          final list = tester
              .widgetList<StremioDropdown<int>>(
                find.byType(StremioDropdown<int>),
              )
              .firstWhere((d) => d.label == 'List');
          list.onSelected(
            list.options.firstWhere((o) => o.label == 'All').value,
          );
          await tester.pump();
        }
        expect(find.byType(SeeAllPosterGrid), findsOneWidget);
        identity.complete(http.Response('{"imdb_id":"tt1234567"}', 200));
        await tester.pumpAndSettle();
        expect(find.byType(SeeAllPosterGrid), findsNothing);
        expect(
          find.text(all ? 'Nothing in this folder' : 'Nothing in this list'),
          findsOneWidget,
        );
        final sort = tester
            .widgetList<StremioDropdown<String>>(
              find.byType(StremioDropdown<String>),
            )
            .firstWhere((d) => d.label == 'Sort');
        sort.focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final retry = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Retry'),
        );
        expect(retry.focusNode!.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final tv in [false, true]) {
    testWidgets(
      'native folder browses without addons; imported tabs win (TV $tv)',
      (tester) async {
        await tester.binding.setSurfaceSize(
          tv ? const Size(1280, 720) : const Size(390, 844),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final native = service();
        addTearDown(native.close);
        StremioMeta? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionFolderScreen(
              collection: collection(viewMode: 'TABBED_GRID'),
              nativeSources: native,
              isTelevision: tv,
              onOpenItem: (item) => opened = item,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SeeAllPosterGrid), findsOneWidget);
        final dropdowns = tester.widgetList<StremioDropdown<int>>(
          find.byType(StremioDropdown<int>),
        );
        if (tv) expect(dropdowns.any((d) => d.label == 'List'), true);
        final grid = tester.widget<SeeAllPosterGrid>(
          find.byType(SeeAllPosterGrid),
        );
        expect(grid.items.single.name, 'Native movie');
        if (tv) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
        } else {
          grid.onOpen(grid.items.single);
        }
        expect(opened?.id, 'tmdb:42');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'native gallery card pushes a grid and Back restores its gallery',
    (tester) async {
      final native = service();
      addTearDown(native.close);
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionFolderScreen(
            collection: collection(viewMode: 'FOLLOW_LAYOUT'),
            nativeSources: native,
            onOpenItem: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CollectionListGallery), findsOneWidget);
      await tester.tap(find.text('New movies'));
      await tester.pumpAndSettle();
      final child = tester.widget<CollectionFolderScreen>(
        find.byType(CollectionFolderScreen),
      );
      expect(child.sourceKey, collection().folders.single.sources.single.key);
      expect(find.text('See all'), findsNothing);
      final grid = tester.widget<SeeAllPosterGrid>(
        find.byType(SeeAllPosterGrid),
      );
      expect(grid.items.single.name, 'Native movie');
      Navigator.of(tester.element(find.byType(SeeAllPosterGrid))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(CollectionListGallery), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in ['cancel', 'replace', 'refresh']) {
    final cancel = action == 'cancel';
    final refresh = action == 'refresh';
    testWidgets('TV pending title handles $action', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <String, Completer<http.Response>>{};
      var opening = false;
      final native = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        enrichmentBudget: const Duration(seconds: 10),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/external_ids')) {
            if (!opening) return http.Response('{}', 503);
            final id = request.url.path.split('/')[3];
            return requests
                .putIfAbsent(id, Completer<http.Response>.new)
                .future;
          }
          return http.Response(
            '{"results":[{"id":42,"title":"First"},{"id":43,"title":"Second"}],"total_pages":1}',
            200,
          );
        }),
      );
      addTearDown(native.close);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionFolderScreen(
            collection: collection(viewMode: 'TABBED_GRID'),
            nativeSources: native,
            isTelevision: true,
            onOpenItem: (m) => opened.add(m.name),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await HomeCollectionsStore.instance.saveCollections([
        collection(viewMode: 'TABBED_GRID'),
      ]);
      opening = true;
      final grid = tester.widget<SeeAllPosterGrid>(
        find.byType(SeeAllPosterGrid),
      );
      grid.onOpen(grid.items.first);
      await tester.pump();
      expect(find.text('Opening First…'), findsOneWidget);
      if (cancel) {
        await tester.tap(find.text('Cancel'));
        await tester.pump();
      } else if (refresh) {
        MainPageBridge.notifyHomeSettingsChanged();
        await tester.pump();
        await tester.pump();
      } else {
        grid.onOpen(grid.items.last);
        await tester.pump();
        expect(find.text('Opening Second…'), findsOneWidget);
      }
      requests['42']!.complete(http.Response('{"imdb_id":"tt42"}', 200));
      await tester.pump();
      expect(opened, refresh ? ['First'] : isEmpty);
      if (!cancel && !refresh) {
        requests['43']!.complete(http.Response('{"imdb_id":"tt43"}', 200));
      }
      await tester.pumpAndSettle();
      expect(opened, cancel ? isEmpty : [refresh ? 'First' : 'Second']);
      expect(find.textContaining('Opening '), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final tv in [false, true]) {
    testWidgets(
      'cards precede slow IDs and update without changing focus IDs (TV $tv)',
      (tester) async {
        final identity = Completer<http.Response>();
        final native = CollectionNativeSourceService(
          tmdbToken: 'dummy',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/external_ids')) {
              return identity.future;
            }
            return http.Response(
              '{"results":[{"id":42,"title":"Film"}],"total_pages":1}',
              200,
            );
          }),
        );
        addTearDown(native.close);
        StremioMeta? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionFolderScreen(
              collection: collection(viewMode: 'TABBED_GRID'),
              isTelevision: tv,
              nativeSources: native,
              onOpenItem: (item) => opened = item,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        var grid = tester.widget<SeeAllPosterGrid>(
          find.byType(SeeAllPosterGrid),
        );
        expect(grid.items.single.id, 'tmdb:42');
        expect(grid.items.single.effectiveImdbId, isNull);
        identity.complete(http.Response('{"imdb_id":"tt1234567"}', 200));
        await tester.pumpAndSettle();
        grid = tester.widget<SeeAllPosterGrid>(find.byType(SeeAllPosterGrid));
        expect(grid.items.single.id, 'tmdb:42');
        expect(grid.items.single.effectiveImdbId, 'tt1234567');
        grid.onOpen(grid.items.single);
        await tester.pumpAndSettle();
        expect(opened?.id, 'tt1234567');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('opening a native title retries failed IMDb enrichment', (
    tester,
  ) async {
    var lookups = 0;
    final native = CollectionNativeSourceService(
      tmdbToken: 'dummy',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/external_ids')) {
          lookups++;
          return lookups == 1
              ? http.Response('{}', 503)
              : http.Response('{"imdb_id":"tt1234567"}', 200);
        }
        return http.Response(
          '{"results":[{"id":42,"title":"Film"}],"total_pages":1}',
          200,
        );
      }),
    );
    addTearDown(native.close);
    StremioMeta? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: collection(viewMode: 'TABBED_GRID'),
          nativeSources: native,
          onOpenItem: (item) => opened = item,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<SeeAllPosterGrid>(find.byType(SeeAllPosterGrid));
    expect(grid.items.single.id, 'tmdb:42');
    grid.onOpen(grid.items.single);
    await tester.pumpAndSettle();
    expect(lookups, 2);
    expect(opened?.id, 'tt1234567');
  });

  testWidgets(
    'partial unsupported sources remain visible as actionable issues',
    (tester) async {
      final native = service();
      addTearDown(native.close);
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionFolderScreen(
            collection: collection(viewMode: 'TABBED_GRID', unknown: true),
            nativeSources: native,
            onOpenItem: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 source(s) need attention'), findsNothing);
      expect(find.byTooltip('Collection needs attention'), findsOneWidget);
      await tester.tap(find.byTooltip('Collection needs attention'));
      await tester.pumpAndSettle();
      expect(find.text('Unsupported provider: future'), findsOneWidget);
    },
  );

  testWidgets('TV can navigate to empty error details and back', (
    tester,
  ) async {
    final native = service(status: 401);
    addTearDown(native.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: collection(viewMode: 'TABBED_GRID'),
          nativeSources: native,
          isTelevision: true,
          onOpenItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sort = tester
        .widgetList<StremioDropdown<String>>(
          find.byType(StremioDropdown<String>),
        )
        .firstWhere((d) => d.label == 'Sort');
    sort.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final details = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'View details'),
    );
    expect(details.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('TMDB denied access'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(details.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final retry = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Retry'),
    );
    expect(retry.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(details.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(details.focusNode!.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(details.focusNode!.hasFocus, isTrue);
  });

  testWidgets('empty successful tab retains other source diagnostics', (
    tester,
  ) async {
    final native = CollectionNativeSourceService(
      tmdbToken: 'dummy',
      resolveIds: false,
      client: MockClient(
        (_) async => http.Response('{"results":[],"total_pages":1}', 200),
      ),
    );
    addTearDown(native.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: collection(viewMode: 'TABBED_GRID', unknown: true),
          nativeSources: native,
          onOpenItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing in this list'), findsOneWidget);
    expect(find.text('Couldn’t load this collection'), findsNothing);
    expect(find.text('View details'), findsNothing);
    await tester.tap(find.byTooltip('Collection needs attention'));
    await tester.pumpAndSettle();
    expect(find.text('Unsupported provider: future'), findsOneWidget);
  });

  testWidgets('provider denial is shown rather than an empty addon message', (
    tester,
  ) async {
    final native = service(status: 401);
    addTearDown(native.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: collection(viewMode: 'TABBED_GRID'),
          nativeSources: native,
          onOpenItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('TMDB denied access'), findsNothing);
    expect(find.text('Couldn’t load this collection'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TMDB denied access'), findsOneWidget);
    expect(find.text('No matching addon installed'), findsNothing);
  });
  testWidgets(
    'TV gallery opens a list with poster focus and restores its card',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final native = service();
      addTearDown(native.close);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionFolderScreen(
            collection: collection(),
            nativeSources: native,
            isTelevision: true,
            onOpenItem: (item) => opened.add(item.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('collection_list_'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(find.byType(SeeAllPosterGrid), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('seeall_grid_'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(opened, ['tmdb:42']);
      Navigator.of(tester.element(find.byType(SeeAllPosterGrid))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(CollectionListGallery), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('collection_list_'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final style in ['gallery', 'filmstrip', 'journal']) {
    for (final tv in [false, true]) {
      testWidgets('$style collection layout is TV-only (TV $tv)', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          HomeCollectionsStore.folderLayoutKey: 'rows',
          'tv_collection_list_style': style,
        });
        await tester.binding.setSurfaceSize(const Size(960, 540));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final native = service();
        addTearDown(native.close);
        final c = collection();
        final opened = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionFolderScreen(
              collection: c,
              sourceKey: c.folders.first.sources.first.key,
              nativeSources: native,
              isTelevision: tv,
              onOpenItem: (item) => opened.add(item.id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(TvCollectionTitles),
          tv ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(SeeAllPosterGrid),
          tv ? findsNothing : findsOneWidget,
        );
        if (tv) {
          await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
          await tester.pumpAndSettle();
          expect(opened, ['tmdb:42']);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('opened gallery list paginates on touch scroll', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = <int>[];
    final native = CollectionNativeSourceService(
      tmdbToken: 'dummy',
      resolveIds: false,
      client: MockClient((request) async {
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        pages.add(page);
        return http.Response(
          jsonEncode({
            'results': [
              for (var i = 0; i < 20; i++)
                {'id': page * 100 + i, 'title': 'Movie $page $i'},
            ],
            'total_pages': 2,
          }),
          200,
        );
      }),
    );
    addTearDown(native.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: collection(),
          nativeSources: native,
          onOpenItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New movies'));
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
          of: find.byType(SeeAllPosterGrid),
          matching: find.byType(Scrollable),
        )
        .first;
    tester
        .state<ScrollableState>(scroll)
        .position
        .jumpTo(tester.state<ScrollableState>(scroll).position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(pages, contains(2));
    expect(
      tester
          .widget<SeeAllPosterGrid>(find.byType(SeeAllPosterGrid))
          .items
          .length,
      40,
    );
    expect(find.text('Load more'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
