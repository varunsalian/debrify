import 'dart:async';
import 'package:debrify/features/home/application/home_saved_content_providers.dart';
import 'package:debrify/features/home/data/home_tv_favorites_repository.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/home_row_refresh.dart';
import 'package:debrify/services/main_page_bridge.dart';
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
import 'fixtures/tv_favorites_fixture.dart';

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
    'sidebar',
    'profile',
    'dispose',
    'search',
    'discover',
  ]) {
    testWidgets('TV favourites injected reads preserve $mode behavior', (
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
      final pending = Completer<Set<String>>();
      var idReads = 0;
      var channelReads = 0;
      var failed = false;
      var empty = false;
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
              homeTvFavoritesRepositoryProvider.overrideWithValue(
                HomeTvFavoritesRepository(
                  favoriteIds: () {
                    idReads++;
                    return idReads == 1
                        ? pending.future
                        : Future.value(empty ? <String>{} : {'a'});
                  },
                  channels: () async {
                    channelReads++;
                    if (failed) throw StateError('channel database');
                    return [channel('a').copyWith(name: 'One')];
                  },
                ),
              ),
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
      expect(idReads, home ? 1 : 0);
      expect(channelReads, 0);
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
      await drive(() => pending.complete({'a'}));
      await tester.pump(const Duration(milliseconds: 100));
      Iterable<FocusNode> nodes() => find
          .text('One')
          .evaluate()
          .map((e) => Focus.maybeOf(e))
          .whereType<FocusNode>();
      if (mode == 'home' || mode == 'sidebar') {
        expect(channelReads, 1);
        final node = nodes().single;
        node.requestFocus();
        await tester.pump();
        if (mode == 'sidebar') {
          final previous = MainPageBridge.focusTvSidebar;
          addTearDown(() => MainPageBridge.focusTvSidebar = previous);
          var originalCalls = 0;
          var replacementCalls = 0;
          MainPageBridge.focusTvSidebar = () => originalCalls++;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          expect(originalCalls, 1);
          MainPageBridge.focusTvSidebar = () => replacementCalls++;
          // No rebuild: the route's current sidebar callback must be read live.
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          expect(originalCalls, 1);
          expect(replacementCalls, 1);
        }
        failed = true;
        await drive(() => HomeRowRefreshSignal.dispatch({'tv/ch'}));
        await tester.pump(const Duration(milliseconds: 100));
        expect(idReads, 2);
        expect(channelReads, 2);
        expect(nodes().single, same(node));
        expect(node.hasFocus, isTrue);
        empty = true;
        await drive(
          () => HomeRowRefreshSignal.dispatch({
            'debrify_tv_favorite_channels_v1',
          }),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(idReads, 3);
        expect(channelReads, 2);
        expect(nodes(), isEmpty);
      } else {
        expect(channelReads, 0);
        expect(nodes(), isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
