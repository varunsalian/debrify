import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/data/home_continuation_layout_repository.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'dart:async';

import 'package:debrify/features/home/data/home_local_continuation_repository.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/search_screen.dart';
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

void main() {
  for (final outcome in ['active', 'profile', 'dispose', 'disabled']) {
    testWidgets('local Home continuation uses scoped reads: $outcome', (
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
      });
      StorageService.tvHomeStyleCached = 'classic';
      StremioService.instance.invalidateCache();
      addTearDown(() {
        PlatformUtil.debugSetAndroidTvCached(null);
        PlatformUtil.debugSetTvOS(null);
        ProfileRuntime.debugReset();
      });
      final calls = <String>[];
      final layoutReads = <String>[];
      final first = Completer<Map<String, dynamic>?>();
      final repository = HomeLocalContinuationRepository(
        readProgressSource: () async {
          calls.add('source');
          return WatchProgressSource.local;
        },
        readEnabled: () async {
          calls.add('enabled');
          return outcome != 'disabled';
        },
        readItems: () async {
          calls.add('items');
          return [
            {'imdbId': 'tmdb:movie:1', 'title': 'Local fixture'},
            {'imdbId': 'tmdb:movie:2', 'title': 'Second local fixture'},
            {'imdbId': 'tmdb:3', 'title': 'Series fixture', 'type': 'series'},
          ];
        },
        readAddons: () => throw StateError('Unexpected addons'),
        readEpisode: (id) async {
          calls.add(id);
          return null;
        },
        readMovie: (id) {
          calls.add(id);
          return id == 'tmdb:movie:1' ? first.future : Future.value(null);
        },
      );
      final client = MockClient((_) async => http.Response('[]', 200));
      await tester.runAsync(
        () => http.runWithClient(() async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                homeContinuationLayoutRepositoryProvider.overrideWithValue(
                  HomeContinuationLayoutRepository(
                    readMerged: (provider) {
                      layoutReads.add(provider);
                      return StorageService.getHomeCwMergedRows(provider);
                    },
                  ),
                ),
                homeLocalContinuationRepositoryProvider.overrideWithValue(
                  repository,
                ),
              ],
              child: const MaterialApp(home: SearchScreen(isTelevision: true)),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }, () => client),
      );
      expect(
        calls,
        outcome == 'disabled'
            ? ['source', 'enabled']
            : ['source', 'enabled', 'items', 'tmdb:movie:1'],
      );
      if (outcome == 'dispose') await tester.pumpWidget(const SizedBox());
      if (outcome == 'profile') {
        ProfileRuntime.promoteLegacyToCommitted(
          ProfileScope(
            profileId: 'incoming',
            dataGeneration: 1,
            sessionEpoch: 1,
          ),
        );
      }
      await tester.runAsync(() async {
        first.complete({'positionMs': 500, 'durationMs': 1000});
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 500));
      if (outcome == 'active') {
        expect(calls, [
          'source',
          'enabled',
          'items',
          'tmdb:movie:1',
          'tmdb:movie:2',
          'tmdb:3',
        ]);
        expect(find.text('Local fixture'), findsWidgets);
        FocusNode cardNode() => find
            .text('Local fixture')
            .evaluate()
            .map((element) => Focus.maybeOf(element))
            .whereType<FocusNode>()
            .single;
        final node = cardNode();
        node.requestFocus();
        await http.runWithClient(() => tester.pump(), () => client);
        expect(node.hasFocus, isTrue);
        await tester.runAsync(() async {
          StorageService.localCompletionRevision.value++;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await http.runWithClient(
          () => tester.pump(const Duration(milliseconds: 100)),
          () => client,
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(calls, [
          'source',
          'enabled',
          'items',
          'tmdb:movie:1',
          'tmdb:movie:2',
          'tmdb:3',
          'source',
          'enabled',
          'items',
          'tmdb:movie:1',
          'tmdb:movie:2',
          'tmdb:3',
        ]);
        expect(cardNode(), same(node));
        expect(node.hasFocus, isTrue);
        expect(layoutReads, ['local', 'trakt', 'simkl', 'mdblist']);
        final historyReads = List<String>.of(calls);
        for (final merged in [true, false]) {
          await tester.runAsync(() async {
            await StorageService.setHomeCwMergedRows('local', merged);
            MainPageBridge.notifyHomeSettingsChanged();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await http.runWithClient(
            () => tester.pump(const Duration(milliseconds: 100)),
            () => client,
          );
          expect(cardNode(), same(node));
          expect(node.hasFocus, isTrue);
          expect(calls, historyReads);
          if (merged) {
            final seriesNode = find
                .text('Series fixture')
                .evaluate()
                .map((element) => Focus.maybeOf(element))
                .whereType<FocusNode>()
                .single;
            expect(seriesNode.debugLabel, 'search_cw_movie_2');
          }
        }
        expect(layoutReads, [
          for (var i = 0; i < 3; i++) ...['local', 'trakt', 'simkl', 'mdblist'],
        ]);
      } else {
        expect(calls, isNot(contains('tmdb:movie:2')));
        expect(find.text('Local fixture'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
