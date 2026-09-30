import 'dart:convert';

import 'package:debrify/features/home/presentation/home_board_cell.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Same fonts, platform/preferences setup, HTTP fake and themed SearchScreen
// harness as home_progressive_screen_test.dart, with a fixed two-row catalog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Roboto', 'Inter', 'Poppins']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'));
      await loader.load();
    }
  });
  for (final style in [
    'classic',
    'spotlight',
    'canvas',
    'promenade',
    'atrium',
    'mosaic',
    'deck',
    'tonight',
  ]) {
    testWidgets('$style retains card identity through D-pad navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppThemeAdapter.debugUseTestTypography = true;
      addTearDown(() => AppThemeAdapter.debugUseTestTypography = false);
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      PlatformUtil.debugSetAndroidTvCached(true);
      PlatformUtil.debugSetTvOS(false);
      final previousTab = MainPageBridge.activeTvTabIndex;
      MainPageBridge.setActiveTvTab(15);
      addTearDown(() {
        PlatformUtil.debugSetAndroidTvCached(null);
        PlatformUtil.debugSetTvOS(null);
        MainPageBridge.setActiveTvTab(previousTab);
      });
      final addon = StremioAddon(
        id: 'navigation',
        name: 'Navigation',
        baseUrl: 'https://home.invalid',
        manifestUrl: 'https://home.invalid/manifest.json',
        resources: ['catalog'],
        catalogs: [
          for (var row = 0; row < 2; row++)
            StremioAddonCatalog(id: 'row$row', type: 'movie', name: 'Row $row'),
        ],
      );
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': jsonEncode([addon.toJson()]),
        'tv_home_style': style,
        'home_hero_source_v1': jsonEncode({
          'mode': 'custom',
          'ids': ['navigation:movie:row0'],
        }),
      });
      StorageService.tvHomeStyleCached = style;
      StremioService.instance.invalidateCache();
      final client = MockClient((request) async {
        if (request.url.host != 'home.invalid') return http.Response('', 404);
        if (!request.url.path.contains('/catalog/')) {
          return http.Response('{}', 200);
        }
        final row = request.url.path.contains('row1') ? 1 : 0;
        return http.Response(
          jsonEncode({
            'metas': [
              for (var col = 0; col < 3; col++)
                {
                  'id': 'fixture:$row:$col',
                  'type': 'movie',
                  'name': 'Card $row $col',
                },
            ],
          }),
          200,
        );
      });
      await http.runWithClient(() async {
        await tester.runAsync(
          () => http.runWithClient(() async {
            await StremioService.instance.getCatalogAddons();
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: AppThemeAdapter.themed(
                    AppTheme.fromDetail(DetailThemes.byId('signal')),
                    TextBrightness.bright,
                  ),
                  home: AppThemeScope(
                    theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
                    child: const SearchScreen(isTelevision: true),
                  ),
                ),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await tester.pump();
          }, () => client),
        );
        await tester.pump(const Duration(milliseconds: 500));
        // Begin at the first catalog card, independent of each layout's initial
        // hero autofocus. Card identities are metadata keys; the existing
        // HomeBoardCell widgets themselves do not have Flutter widget keys.
        final first = find.text('Card 0 0').last;
        await tester.ensureVisible(first);
        Focus.of(tester.element(first)).requestFocus();
        await tester.pump(const Duration(milliseconds: 500));
        String focusedCard() {
          final cards = tester.widgetList<HomeBoardCell>(
            find.byType(HomeBoardCell),
          );
          for (final card in cards) {
            if (card.focusNode.hasFocus) return card.item.id;
          }
          final spotlight = find.byType(SpotlightBoard);
          if (spotlight.evaluate().isNotEmpty) {
            final board = tester.widget<SpotlightBoard>(spotlight);
            for (final section in board.sections) {
              for (var i = 0; i < section.nodes.length; i++) {
                if (section.nodes[i].hasFocus) {
                  return section.items[i].metadata!.id;
                }
              }
            }
            if (board.heroNode.hasFocus) return 'hero';
          }
          return 'other:${FocusManager.instance.primaryFocus?.debugLabel}';
        }

        expect(focusedCard(), 'fixture:0:0');
        for (final (key, expectedCardKey) in [
          (LogicalKeyboardKey.arrowDown, 'fixture:1:0'),
          (LogicalKeyboardKey.arrowRight, 'fixture:1:1'),
          (LogicalKeyboardKey.arrowLeft, 'fixture:1:0'),
          (LogicalKeyboardKey.arrowUp, 'fixture:0:0'),
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            focusedCard(),
            expectedCardKey,
            reason: '$style ${key.keyLabel}',
          );
          expect(tester.takeException(), isNull);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(MergedDetailScreen), findsOneWidget);
        expect(
          tester
              .widget<MergedDetailScreen>(find.byType(MergedDetailScreen))
              .item
              .id,
          'fixture:0:0',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }, () => client);
    });
  }
}
