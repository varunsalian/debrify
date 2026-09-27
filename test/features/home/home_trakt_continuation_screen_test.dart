import 'package:debrify/features/home/application/home_watchlist_dependencies.dart';
import 'package:debrify/features/home/application/home_local_continuation_dependencies.dart';
import 'package:debrify/features/home/application/home_iptv_continuation_dependencies.dart';
import 'package:debrify/features/home/application/home_bound_counts_dependencies.dart';
import 'package:debrify/features/home/data/home_bound_counts_repository.dart';
import 'package:debrify/services/iptv_cw_history.dart';
import 'fixtures/home_continuation_fixture.dart' show continuationRepository;
import 'package:debrify/screens/see_all/trakt_see_all_screen.dart';
import 'package:debrify/features/home/models/home_trakt_continuation_state.dart';
import 'dart:async';

import 'package:debrify/features/home/application/home_trakt_continuation_dependencies.dart';
import 'package:debrify/features/home/data/home_trakt_continuation_repository.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt_continue_watching_item.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class TraktStateObserver extends ProviderObserver {
  final updates = <HomeTraktContinuationState>[];
  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (newValue is HomeTraktContinuationState) updates.add(newValue);
  }
}

void main() {
  for (final mode in [
    'active',
    'playback',
    'profile',
    'dispose',
    'overlap',
    'search',
    'discover',
  ]) {
    testWidgets('Trakt Home reads scoped repository: $mode', (tester) async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      PlatformUtil.debugSetAndroidTvCached(false);
      PlatformUtil.debugSetTvOS(false);
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': '[]',
        'tv_home_style': 'classic',
        if (mode == 'discover') 'discover_default_source': 'trakt',
        'home_hero_source_v1': '{"mode":"auto","ids":[]}',
      });
      StorageService.tvHomeStyleCached = 'classic';
      StremioService.instance.invalidateCache();
      addTearDown(() {
        PlatformUtil.debugSetAndroidTvCached(null);
        PlatformUtil.debugSetTvOS(null);
        ProfileRuntime.debugReset();
      });
      final rows = [
        TraktContinueWatchingItem(
          meta: StremioMeta(
            id: 'tmdb:movie:1',
            name: 'Trakt fixture',
            type: 'movie',
          ),
          traktContentType: 'movies',
          progress: 50,
        ),
      ];
      final pending = Completer<List<TraktContinueWatchingItem>?>();
      var authenticated = true;
      var fail = false;
      final calls = <String>[];
      final observer = TraktStateObserver();
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
            observers: [observer],
            overrides: [
              if (mode == 'playback') ...[
                homeWatchlistReaderProvider.overrideWithValue(() async => []),
                homeLocalContinuationRepositoryProvider.overrideWithValue(
                  continuationRepository(readItems: () async => []),
                ),
                homeIptvContinuationRepositoryProvider.overrideWithValue(
                  IptvCwHistory(readHistory: () async => []),
                ),
                homeBoundCountsRepositoryProvider.overrideWith(
                  (ref, session) =>
                      HomeBoundCountsRepository(readCount: (_, _) async => 0),
                ),
              ],
              homeTraktContinuationRepositoryProvider.overrideWithValue(
                HomeTraktContinuationRepository(
                  isAuthenticated: () async {
                    calls.add('auth');
                    return authenticated;
                  },
                  readMovies: () {
                    calls.add('movies');
                    if (fail) return Future.value(null);
                    if (mode == 'overlap' &&
                        calls.where((c) => c == 'movies').length > 1) {
                      return Future.value([
                        TraktContinueWatchingItem(
                          meta: StremioMeta(
                            id: 'tmdb:movie:2',
                            name: 'Latest Trakt fixture',
                            type: 'movie',
                          ),
                          traktContentType: 'movies',
                        ),
                      ]);
                    }
                    return calls.where((call) => call == 'movies').length == 1
                        ? pending.future
                        : Future.value(rows);
                  },
                  readShows: () async {
                    calls.add('shows');
                    return [];
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
      expect(calls, mode == 'search' ? [] : ['auth', 'movies', 'shows']);
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
        await drive(MainPageBridge.notifyIntegrationChanged);
        await pump();
        expect(find.text('Latest Trakt fixture'), findsWidgets);
      }
      await drive(() => pending.complete(rows));
      await pump();
      Iterable<FocusNode> cardNodes() => find
          .text('Trakt fixture')
          .evaluate()
          .map((element) => Focus.maybeOf(element))
          .whereType<FocusNode>();
      if (mode == 'playback') {
        addTearDown(MainPageBridge.notifyContentPlaybackStopped);
        Future<void> returnFromPlayback({bool? trailer}) async {
          await drive(() {
            if (trailer != null) {
              MainPageBridge.notifyPlayerLaunching(isTrailer: trailer);
            }
            MainPageBridge.notifyPlaybackReturned();
          });
          for (var i = 0; i < 4; i++) {
            await drive(() {});
            await pump();
          }
        }

        await returnFromPlayback(trailer: true);
        expect(calls, ['auth', 'movies', 'shows']);
        await returnFromPlayback(trailer: false);
        expect(calls, ['auth', 'movies', 'shows', 'auth', 'movies', 'shows']);
        await returnFromPlayback();
        expect(calls, ['auth', 'movies', 'shows', 'auth', 'movies', 'shows']);
        expect(cardNodes(), isNotEmpty);
      } else if (mode == 'active') {
        final node = cardNodes().single;
        node.requestFocus();
        await pump();
        expect(node.hasFocus, isTrue);
        fail = true;
        await drive(MainPageBridge.notifyIntegrationChanged);
        await pump();
        expect(calls, ['auth', 'movies', 'shows', 'auth', 'movies', 'shows']);
        expect(cardNodes().single, same(node));
        expect(node.hasFocus, isTrue);
        authenticated = false;
        await drive(MainPageBridge.notifyIntegrationChanged);
        await pump();
        expect(calls, [
          'auth',
          'movies',
          'shows',
          'auth',
          'movies',
          'shows',
          'auth',
        ]);
        expect(cardNodes(), isEmpty);
      } else if (mode == 'search' || mode == 'discover') {
        expect(calls, mode == 'search' ? [] : ['auth', 'movies', 'shows']);
        if (mode == 'search') {
          expect(observer.updates, isEmpty);
        } else {
          expect(observer.updates.last.loading, isFalse);
          expect(
            observer.updates.last.data.movies.single.name,
            'Trakt fixture',
          );
          final retainedProgress = tester
              .widget<TraktSeeAllScreen>(find.byType(TraktSeeAllScreen))
              .cwProgress;
          expect(retainedProgress['tmdb:movie:1'], .5);
          rows[0] = TraktContinueWatchingItem(
            meta: rows[0].meta,
            traktContentType: 'movies',
            progress: 75,
          );
          await drive(MainPageBridge.notifyIntegrationChanged);
          await pump();
          expect(observer.updates.last.loading, isFalse);
          expect(observer.updates.last.data.progress['tmdb:movie:1'], .75);
          expect(retainedProgress['tmdb:movie:1'], .75);
        }
      } else {
        expect(cardNodes(), isEmpty);
        expect(
          calls,
          mode == 'overlap'
              ? ['auth', 'movies', 'shows', 'auth', 'movies', 'shows']
              : ['auth', 'movies', 'shows'],
        );
        if (mode == 'overlap') {
          expect(find.text('Latest Trakt fixture'), findsWidgets);
        }
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
