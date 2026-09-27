import 'dart:async';
import 'package:debrify/features/home/application/home_watchlist_dependencies.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/home_row_refresh.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Match the app's line metrics instead of the square Ahem test font.
    for (final family in ['Roboto', 'Inter', 'Poppins']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'));
      await loader.load();
    }
  });
  for (final mode in [
    'home',
    'overlap',
    'profile',
    'dispose',
    'search',
    'discover',
  ]) {
    testWidgets('Watchlist injected reads preserve $mode behavior', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
      final pending = Completer<List<StremioMeta>>();
      var reads = 0;
      var failed = false;
      var empty = false;
      var shrink = false;
      List<StremioMeta> titles() => [
        const StremioMeta(id: 'one', name: 'One', type: 'movie'),
        if (!shrink) const StremioMeta(id: 'two', name: 'Two', type: 'movie'),
        const StremioMeta(id: 'show', name: 'Show', type: 'series'),
      ];
      final client = MockClient((_) async => http.Response('[]', 200));
      Future<void> drive(FutureOr<void> Function() action) => tester.runAsync(
        () => http.runWithClient(() async {
          await action();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }, () => client),
      );
      await drive(
        () => tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeWatchlistReaderProvider.overrideWithValue(() {
                reads++;
                if (reads == 1) return pending.future;
                if (failed && !empty && !shrink) {
                  return Future.error(StateError('store'));
                }
                return Future.value(empty ? <StremioMeta>[] : titles());
              }),
            ],
            child: MaterialApp(
              home: SearchScreen(
                isTelevision: true,
                searchMode: mode == 'search',
                discoverMode: mode == 'discover',
              ),
            ),
          ),
        ),
      );
      final home = mode != 'search' && mode != 'discover';
      expect(reads, home ? 1 : 0);
      if (mode == 'dispose') await tester.pumpWidget(const SizedBox());
      if (mode == 'profile') {
        ProfileRuntime.promoteLegacyToCommitted(
          ProfileScope(
            profileId: 'incoming',
            dataGeneration: 1,
            sessionEpoch: 1,
          ),
        );
      }
      if (mode == 'overlap') {
        await drive(() => HomeRowRefreshSignal.dispatch({'my_watchlist_v1'}));
        await tester.pump(const Duration(milliseconds: 100));
        expect(reads, 2);
        expect(find.text('One'), findsOneWidget);
      }
      await drive(
        () => pending.complete(
          mode == 'overlap'
              ? [const StremioMeta(id: 'old', name: 'Old', type: 'movie')]
              : titles(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      Iterable<FocusNode> nodes([String title = 'One']) => find
          .text(title)
          .evaluate()
          .map((e) => Focus.maybeOf(e))
          .whereType<FocusNode>();
      if (mode == 'home' || mode == 'overlap') {
        expect(find.text('Old'), findsNothing);
        expect(find.text('Show'), findsOneWidget);
        final node = nodes('Two').single;
        node.requestFocus();
        await tester.pump();
        failed = true;
        await drive(() => HomeRowRefreshSignal.dispatch({'my_watchlist_v1'}));
        await tester.pump(const Duration(milliseconds: 100));
        expect(reads, mode == 'overlap' ? 3 : 2);
        expect(nodes('Two').single, same(node));
        expect(node.hasFocus, isTrue);
        shrink = true;
        await drive(() => HomeRowRefreshSignal.dispatch({'my_watchlist_v1'}));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(nodes('Two'), isEmpty);
        expect(nodes().single.hasFocus, isTrue);
        empty = true;
        await drive(() => HomeRowRefreshSignal.dispatch({'my_watchlist_v1'}));
        await tester.pump(const Duration(milliseconds: 100));
        expect(reads, mode == 'overlap' ? 5 : 4);
        expect(nodes(), isEmpty);
        expect(find.text('Show'), findsNothing);
      } else {
        expect(nodes(), isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
