import 'dart:async';

import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/models/home_iptv_continuation_state.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/iptv_cw_history.dart';
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

final class IptvObserver extends ProviderObserver {
  final updates = <HomeIptvContinuationState>[];
  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (newValue is HomeIptvContinuationState) updates.add(newValue);
  }
}

void main() {
  for (final mode in ['home', 'search', 'discover', 'profile', 'dispose']) {
    testWidgets(
      'IPTV Home state uses scoped loading and original tab policy: $mode',
      (tester) async {
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
        final rows = <Map<String, dynamic>>[
          {
            'url': 'https://fixture.invalid/vod',
            'name': 'IPTV fixture',
            'progress': 0.5,
          },
        ];
        final response = Completer<List<Map<String, dynamic>>>();
        var reads = 0;
        final observer = IptvObserver();
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
                homeIptvContinuationRepositoryProvider.overrideWithValue(
                  IptvCwHistory(
                    readHistory: () {
                      reads++;
                      return reads == 1 ? response.future : Future.value(rows);
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
        expect(reads, mode == 'search' || mode == 'discover' ? 0 : 1);
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
        await drive(() => response.complete(rows));
        await pump();
        if (mode == 'home') {
          expect(observer.updates.last.movies.single.name, 'IPTV fixture');
          FocusNode cardNode() => find
              .text('IPTV fixture')
              .evaluate()
              .map((e) => Focus.maybeOf(e))
              .whereType<FocusNode>()
              .single;
          final node = cardNode();
          node.requestFocus();
          await pump();
          expect(node.hasFocus, isTrue);
          await drive(MainPageBridge.notifyPlaybackDataChanged);
          await pump();
          expect(reads, 2);
          expect(cardNode(), same(node));
          expect(node.hasFocus, isTrue);
        } else if (mode == 'search' || mode == 'discover') {
          expect(observer.updates, isEmpty);
          await drive(MainPageBridge.notifyPlaybackDataChanged);
          await pump();
          expect(reads, mode == 'search' ? 0 : 1);
          if (mode == 'discover') {
            expect(observer.updates.last.movies.single.name, 'IPTV fixture');
          }
        } else {
          expect(observer.updates, isEmpty);
          expect(find.text('IPTV fixture'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
