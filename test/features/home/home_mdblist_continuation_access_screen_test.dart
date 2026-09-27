import 'dart:async';
import 'package:debrify/features/home/application/home_mdblist_continuation_dependencies.dart';
import 'package:debrify/features/home/data/home_mdblist_continuation_repository.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
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
  for (final mode in ['home', 'profile', 'dispose', 'search', 'discover']) {
    testWidgets('MDBList scoped access preserves $mode sequencing', (
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
      final pending = Completer<bool>();
      final calls = <Object>[];
      final client = MockClient((_) async => http.Response('[]', 200));
      Future<void> drive(FutureOr<void> Function() action) => tester.runAsync(
        () => http.runWithClient(() async {
          await action();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }, () => client),
      );
      await drive(
        () => tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeMdblistContinuationRepositoryProvider.overrideWithValue(
                HomeMdblistContinuationRepository(
                  synchronizeInvalidations: () {
                    calls.add('sync');
                    return calls.length == 1
                        ? pending.future
                        : Future.value(true);
                  },
                  fetch: ({required force}) async {
                    calls.add(force);
                    return const MdblistResult.partial(
                      MdblistContinueWatchingSnapshot(),
                    );
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
      expect(calls, mode == 'search' ? [] : ['sync']);
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
      await drive(() => pending.complete(false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        calls,
        mode == 'search'
            ? []
            : mode == 'profile' || mode == 'dispose'
            ? ['sync']
            : ['sync', false],
      );
      if (mode == 'home') {
        await drive(() async {
          MdblistService.instance.playbackRevision.value++;
          await Future<void>.delayed(const Duration(milliseconds: 900));
        });
        await tester.pump(const Duration(milliseconds: 100));
        expect(calls, ['sync', false, 'sync', true]);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
