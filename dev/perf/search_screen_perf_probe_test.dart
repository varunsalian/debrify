// Host-side performance probe for SearchScreen (not part of the test suite).
//
// Runs fixed scenarios against fixed fixtures and prints one JSON line per
// scenario: network requests (count and ordered paths), widget rebuilds while
// the scenario runs, and pumps until the first content is visible. Run the same
// file on two revisions and compare the lines:
//
//   flutter test dev/perf/search_screen_perf_probe_test.dart
//
// Numbers are deterministic for a given revision because time is driven by
// fixed pump windows. They are not frame timings; on-device profiling stays a
// separate, manual check.
//
// It lives outside test/ so the regular suite does not run it, but it drives
// the same test-only hooks the suite uses.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rows = 12;
const _cards = 10;

StremioAddon _addon() => StremioAddon(
  id: 'perf',
  name: 'Perf',
  baseUrl: 'https://perf.invalid',
  manifestUrl: 'https://perf.invalid/manifest.json',
  resources: ['catalog'],
  catalogs: [
    for (var row = 0; row < _rows; row++)
      StremioAddonCatalog(
        id: 'row$row',
        type: 'movie',
        name: 'Row $row',
        extraSupported: const ['search'],
      ),
  ],
);

MockClient _client(List<String> log) => MockClient((request) async {
  log.add(
    '${request.url.path}${request.url.hasQuery ? '?${request.url.query}' : ''}',
  );
  if (request.url.host != 'perf.invalid') return http.Response('{}', 404);
  final match = RegExp(r'/catalog/movie/row(\d+)').firstMatch(request.url.path);
  if (match == null) return http.Response('{}', 200);
  final row = int.parse(match.group(1)!);
  return http.Response(
    jsonEncode({
      'metas': [
        for (var col = 0; col < _cards; col++)
          {'id': 'fx:$row:$col', 'type': 'movie', 'name': 'Card $row $col'},
      ],
    }),
    200,
  );
});

Future<void> _setUp({required bool tv}) async {
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  PlatformUtil.debugSetAndroidTvCached(tv);
  PlatformUtil.debugSetTvOS(false);
  SharedPreferences.setMockInitialValues({
    'stremio_addons_v1': jsonEncode([_addon().toJson()]),
    'tv_home_style': 'classic',
  });
  StorageService.tvHomeStyleCached = 'classic';
  StremioService.instance.invalidateCache();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var rebuilds = 0;
  setUp(() {
    // Bundled test typography: no network font fetches during measurement.
    AppThemeAdapter.debugUseTestTypography = true;
    rebuilds = 0;
    debugOnRebuildDirtyWidget = (_, _) => rebuilds++;
  });
  tearDown(() {
    AppThemeAdapter.debugUseTestTypography = false;
    debugOnRebuildDirtyWidget = null;
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
    ProfileRuntime.debugReset();
  });

  Future<int> pumpUntil(WidgetTester tester, Finder finder, int max) async {
    for (var i = 1; i <= max; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return i;
    }
    return -1;
  }

  Future<void> settle(WidgetTester tester, int windows) async {
    for (var i = 0; i < windows; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void report(String scenario, List<String> log, int rebuildCount, int first) {
    // ignore: avoid_print
    print(
      'PERF ${jsonEncode({'scenario': scenario, 'requests': log.length, 'rebuilds': rebuildCount, 'pumpsToFirstContent': first, 'paths': log})}',
    );
  }

  for (final tv in [true, false]) {
    testWidgets('home first load and paging (tv=$tv)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final previousTab = MainPageBridge.activeTvTabIndex;
      MainPageBridge.setActiveTvTab(15);
      addTearDown(() => MainPageBridge.setActiveTvTab(previousTab));
      await _setUp(tv: tv);
      final log = <String>[];
      await http.runWithClient(() async {
        await tester.runAsync(
          () => http.runWithClient(() async {
            await StremioService.instance.getCatalogAddons();
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(home: SearchScreen(isTelevision: tv)),
              ),
            );
          }, () => _client(log)),
        );
        final first = await pumpUntil(
          tester,
          find.text('Card 0 0', skipOffstage: false),
          120,
        );
        await settle(tester, 30);
        report('home_first_load tv=$tv', [...log], rebuilds, first);

        final before = log.length;
        rebuilds = 0;
        final scrollable = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first;
        for (var i = 0; i < 12; i++) {
          await tester.drag(scrollable, const Offset(0, -900));
          await settle(tester, 6);
        }
        report('home_paging tv=$tv', log.sublist(before), rebuilds, -1);
        await tester.pumpWidget(const SizedBox());
        await settle(tester, 20);
      }, () => _client(log));
    });

    testWidgets('catalog search (tv=$tv)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final previousTab = MainPageBridge.activeTvTabIndex;
      MainPageBridge.setActiveTvTab(17);
      addTearDown(() => MainPageBridge.setActiveTvTab(previousTab));
      await _setUp(tv: tv);
      final log = <String>[];
      await http.runWithClient(() async {
        await tester.runAsync(
          () => http.runWithClient(() async {
            await StremioService.instance.getCatalogAddons();
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  home: SearchScreen(isTelevision: tv, searchMode: true),
                ),
              ),
            );
          }, () => _client(log)),
        );
        await settle(tester, 20);
        final before = log.length;
        rebuilds = 0;
        await tester.enterText(find.byType(EditableText).first, 'card');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        final first = await pumpUntil(
          tester,
          find.text('Card 0 0', skipOffstage: false),
          120,
        );
        await settle(tester, 30);
        report('catalog_search tv=$tv', log.sublist(before), rebuilds, first);
        await tester.pumpWidget(const SizedBox());
        await settle(tester, 20);
      }, () => _client(log));
    });
  }
}
