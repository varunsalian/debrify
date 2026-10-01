import 'dart:async';
import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/data/home_simkl_continuation_reader.dart';
import 'package:debrify/models/simkl_continue_watching_item.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/screens/see_all/simkl_see_all_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final mode in ['active', 'profile', 'dispose', 'search', 'discover']) {
    testWidgets('Simkl Home scoped reads preserve $mode behavior', (
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
        if (mode == 'discover') 'discover_default_source': 'simkl',
      });
      HomeAppearanceStorage.tvHomeStyleCached = 'classic';
      StremioService.instance.invalidateCache();
      addTearDown(() {
        PlatformUtil.debugSetAndroidTvCached(null);
        PlatformUtil.debugSetTvOS(null);
        ProfileRuntime.debugReset();
      });
      var percent = 50.0;
      HomeSimklContinuationRows rows() => (
        movies: [
          SimklContinueWatchingItem(
            meta: StremioMeta(
              id: 'tmdb:movie:1',
              name: 'Simkl fixture',
              type: 'movie',
            ),
            progress: percent,
            season: null,
            episode: null,
            pausedAtMs: null,
            isMovie: true,
          ),
        ],
        shows: [],
      );
      final pending = Completer<HomeSimklContinuationRows?>();
      var reads = 0;
      var failed = false;
      var disconnected = false;
      final client = MockClient((_) async => http.Response('[]', 200));
      Future<void> drive(FutureOr<void> Function() action) => tester.runAsync(
        () => http.runWithClient(() async {
          await action();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }, () => client),
      );
      Future<void> pump() => http.runWithClient(
        () => tester.pump(const Duration(milliseconds: 100)),
        () => client,
      );
      await drive(
        () => tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeSimklContinuationReaderProvider.overrideWithValue(() {
                reads++;
                if (reads == 1) return pending.future;
                return Future.value(
                  failed
                      ? null
                      : disconnected
                      ? (
                          movies: <SimklContinueWatchingItem>[],
                          shows: <SimklContinueWatchingItem>[],
                        )
                      : rows(),
                );
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
      expect(reads, mode == 'search' ? 0 : 1);
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
      await drive(() => pending.complete(rows()));
      await pump();
      Iterable<FocusNode> nodes() => find
          .text('Simkl fixture')
          .evaluate()
          .map((e) => Focus.maybeOf(e))
          .whereType<FocusNode>();
      if (mode == 'active') {
        final node = nodes().single;
        node.requestFocus();
        await pump();
        failed = true;
        await drive(MainPageBridge.notifyIntegrationChanged);
        await pump();
        expect(reads, 2);
        expect(nodes().single, same(node));
        expect(node.hasFocus, isTrue);
        failed = false;
        disconnected = true;
        await drive(MainPageBridge.notifyIntegrationChanged);
        await pump();
        expect(reads, 3);
        expect(nodes(), isEmpty);
      } else if (mode == 'discover') {
        final retained = tester
            .widget<SimklSeeAllScreen>(find.byType(SimklSeeAllScreen))
            .cwProgress;
        expect(retained['movie|tmdb:movie:1'], .5);
        percent = 75;
        await drive(MainPageBridge.notifyIntegrationChanged);
        await pump();
        expect(reads, 2);
        expect(retained['movie|tmdb:movie:1'], .75);
      } else {
        expect(nodes(), isEmpty);
        expect(reads, mode == 'search' ? 0 : 1);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
