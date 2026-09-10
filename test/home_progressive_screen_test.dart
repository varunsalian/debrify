import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // The square Ahem test font does not have the production line metrics;
    // exercise TV layout using the app's bundled faces instead.
    for (final family in ['Roboto', 'Inter', 'Poppins']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'));
      await loader.load();
    }
  });
  for (final (android, style) in [
    (true, 'classic'),
    (false, 'classic'),
    (true, 'spotlight'),
  ]) {
    testWidgets(
      'saved collections load before catalogs only on Android TV (android=$android, style=$style)',
      (tester) async {
        final previousTab = MainPageBridge.activeTvTabIndex;
        if (style == 'spotlight') {
          MainPageBridge.setActiveTvTab(15);
          AppThemeAdapter.debugUseTestTypography = true;
          addTearDown(() => AppThemeAdapter.debugUseTestTypography = false);
        }
        addTearDown(() => MainPageBridge.setActiveTvTab(previousTab));
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        PlatformUtil.debugSetAndroidTvCached(android);
        PlatformUtil.debugSetTvOS(!android);
        addTearDown(() {
          PlatformUtil.debugSetAndroidTvCached(null);
          PlatformUtil.debugSetTvOS(null);
        });
        const collection = HomeCollection(
          id: 'local',
          title: 'Saved collection',
          folders: [
            HomeCollectionFolder(id: 'one', title: 'Local folder', sources: []),
          ],
        );
        final addon = StremioAddon(
          id: 'local-test',
          name: 'Test',
          baseUrl: 'https://local.invalid',
          manifestUrl: 'https://local.invalid/manifest.json',
          resources: ['catalog'],
          catalogs: [
            const StremioAddonCatalog(id: 'slow', type: 'movie', name: 'Slow'),
          ],
        );
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1': jsonEncode([addon.toJson()]),
          'home_collections_v1': jsonEncode([collection.toJson()]),
          'tv_home_style': style,
        });
        StorageService.tvHomeStyleCached = style;
        StremioService.instance.invalidateCache();
        final slow = Completer<http.Response>();
        final client = MockClient(
          (request) async => request.url.host == 'local.invalid'
              ? slow.future
              : http.Response('', 404),
        );
        await tester.runAsync(
          () => http.runWithClient(() async {
            await StremioService.instance.getCatalogAddons();
            await tester.pumpWidget(
              MaterialApp(
                home: AppThemeScope(
                  theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
                  child: const SearchScreen(isTelevision: true),
                ),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await tester.pump();
          }, () => client),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.text('Saved collection'),
          android ? findsWidgets : findsNothing,
        );
        FocusNode? earlyCard;
        if (style == 'spotlight') {
          final board = tester.widget<SpotlightBoard>(
            find.byType(SpotlightBoard),
          );
          expect(board.hero, isEmpty);
          earlyCard = FocusManager.instance.primaryFocus;
          expect(board.sections.expand((s) => s.nodes), contains(earlyCard));
          expect(earlyCard, isNot(isA<FocusScopeNode>()));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump();
          expect(FocusManager.instance.primaryFocus, same(earlyCard));
        }
        await tester.runAsync(() async {
          slow.complete(
            http.Response(
              style == 'spotlight'
                  ? '{"metas":[{"id":"late-hero","type":"movie","name":"Late hero"}]}'
                  : '{"metas":[]}',
              200,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Saved collection'), findsWidgets);
        if (style == 'spotlight') {
          final board = tester.widget<SpotlightBoard>(
            find.byType(SpotlightBoard),
          );
          expect(board.hero, isNotEmpty);
          expect(FocusManager.instance.primaryFocus, same(earlyCard));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump(const Duration(milliseconds: 500));
          expect(board.heroNode.hasFocus, isTrue);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final style in [
    'classic',
    'canvas',
    'spotlight',
    'promenade',
    'deck',
    'atrium',
    'tonight',
    'mosaic',
  ]) {
    for (final (covered, paginate) in [
      (false, false),
      (true, false),
      (false, true),
    ]) {
      testWidgets(
        'Android $style handles seven late catalogs (covered=$covered, paginate=$paginate)',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          AppThemeAdapter.debugUseTestTypography = true;
          addTearDown(() => AppThemeAdapter.debugUseTestTypography = false);
          ProfileRuntime.debugReset();
          ProfileRuntime.initializeLegacy();
          PlatformUtil.debugSetAndroidTvCached(true);
          addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
          final addon = StremioAddon(
            id: 'progress',
            name: 'Progress',
            baseUrl: 'https://home.invalid',
            manifestUrl: 'https://home.invalid/manifest.json',
            resources: ['catalog'],
            catalogs: [
              for (var i = 0; i < 7; i++)
                StremioAddonCatalog(
                  id: 'slow$i',
                  type: 'movie',
                  name: 'Slow $i',
                ),
              const StremioAddonCatalog(
                id: 'fast',
                type: 'movie',
                name: 'Fast',
              ),
              if (paginate)
                const StremioAddonCatalog(
                  id: 'tail',
                  type: 'movie',
                  name: 'Tail',
                ),
            ],
          );
          SharedPreferences.setMockInitialValues({
            'stremio_addons_v1': jsonEncode([addon.toJson()]),
            'tv_home_style': style,
            // Random hero selection can independently prefetch the tail;
            // isolate board pagination from that unrelated request path.
            'home_hero_source_v1': jsonEncode({
              'mode': 'custom',
              'ids': ['progress:movie:fast'],
            }),
          });
          StorageService.tvHomeStyleCached = style;
          StremioService.instance.invalidateCache();
          final slow = Completer<http.Response>();
          final navigator = GlobalKey<NavigatorState>();
          final requests = <String>[];
          final client = MockClient((request) async {
            requests.add(request.url.path);
            if (request.url.host != 'home.invalid') {
              return http.Response('', 404);
            }
            if (request.url.path.contains('/slow')) return slow.future;
            return http.Response(
              jsonEncode({
                'metas': [
                  {'id': 'fixture:fast', 'type': 'movie', 'name': 'Fast title'},
                ],
              }),
              200,
            );
          });
          // Pagination now resumes from a post-layout callback. Keep the mock
          // installed during frames and key input too, not just bootstrap.
          await http.runWithClient(() async {
            await tester.runAsync(
              () => http.runWithClient(() async {
                await StremioService.instance.getCatalogAddons();
                await tester.pumpWidget(
                  MaterialApp(
                    theme: AppThemeAdapter.themed(
                      AppTheme.fromDetail(DetailThemes.byId('signal')),
                      TextBrightness.bright,
                    ),
                    navigatorKey: navigator,
                    home: AppThemeScope(
                      theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
                      child: const SearchScreen(isTelevision: true),
                    ),
                  ),
                );
                await Future<void>.delayed(const Duration(milliseconds: 300));
                await tester.pump();
              }, () => client),
            );
            await tester.pump(const Duration(milliseconds: 100));
            expect(requests.any((path) => path.contains('/slow')), isTrue);
            expect(find.text('Fast title'), findsWidgets);
            final card = find.text('Fast title').last;
            await tester.ensureVisible(card);
            await tester.pump(const Duration(milliseconds: 500));
            final focus = Focus.of(tester.element(card));
            focus.requestFocus();
            await tester.pump(const Duration(milliseconds: 500));
            expect(focus.hasFocus, isTrue);
            final before = tester.getTopLeft(card).dy;
            if (paginate) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.pump();
              expect(requests.any((path) => path.contains('/tail')), isFalse);
            }
            if (covered) {
              unawaited(
                navigator.currentState!.push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: Focus(
                        autofocus: true,
                        child: const Text('Cover screen'),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump(const Duration(milliseconds: 500));
              await tester.pump();
            }
            await tester.runAsync(() async {
              slow.complete(
                http.Response(
                  jsonEncode({
                    'metas': [
                      {
                        'id': 'fixture:slow',
                        'type': 'movie',
                        'name': 'Slow title',
                      },
                    ],
                  }),
                  200,
                ),
              );
              await Future<void>.delayed(const Duration(milliseconds: 50));
            });
            await tester.pump(const Duration(milliseconds: 100));
            await tester.pump(const Duration(milliseconds: 500));
            await tester.pump(const Duration(milliseconds: 500));
            if (covered) {
              expect(find.text('Cover screen'), findsOneWidget);
              // The independently selected hero can resolve while covered;
              // the new catalog shelves themselves must remain unmounted.
              expect(find.text('Slow 0', skipOffstage: false), findsNothing);
              navigator.currentState!.pop();
              await tester.pump(const Duration(milliseconds: 500));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));
            }
            if (paginate) {
              await tester.runAsync(
                () async =>
                    Future<void>.delayed(const Duration(milliseconds: 50)),
              );
              await tester.pump(const Duration(milliseconds: 500));
              expect(requests.any((path) => path.contains('/tail')), isTrue);
            } else {
              expect(focus.hasFocus, isTrue);
              expect(find.text('Fast title'), findsWidgets);
              expect(
                tester.getTopLeft(find.text('Fast title').last).dy,
                closeTo(before, 1),
              );
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 2));
            expect(tester.takeException(), isNull);
          }, () => client);
        },
      );
    }
  }
}
