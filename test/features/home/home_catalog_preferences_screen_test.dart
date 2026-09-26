import 'dart:async';

import 'package:debrify/features/home/application/home_catalog_preferences_dependencies.dart';
import 'package:debrify/features/home/data/home_catalog_preferences_repository.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart' show StorageService;
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final retire in [false, true]) {
    testWidgets(
      'Home preference dependency is used by loading/refresh: retire=$retire',
      (tester) async {
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        PlatformUtil.debugSetAndroidTvCached(false);
        PlatformUtil.debugSetTvOS(false);
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1': '[]',
          'tv_home_style': 'classic',
        });
        StorageService.tvHomeStyleCached = 'classic';
        StremioService.instance.invalidateCache();
        addTearDown(() {
          PlatformUtil.debugSetAndroidTvCached(null);
          PlatformUtil.debugSetTvOS(null);
          ProfileRuntime.debugReset();
        });
        final first = Completer<Set<String>>();
        final calls = <String>[];
        final repository = HomeCatalogPreferencesRepository(
          readDisabled: () {
            calls.add('disabled');
            return calls.length == 1 ? first.future : Future.value(<String>{});
          },
          readExtras: () async {
            calls.add('extras');
            return [];
          },
          readRowOrder: () async {
            calls.add('order');
            return [];
          },
          readHeroSource: () async {
            calls.add('hero');
            return (mode: HomeHeroSourceMode.random, ids: <String>[]);
          },
        );
        final client = MockClient((_) async => http.Response('[]', 200));
        await tester.runAsync(
          () => http.runWithClient(() async {
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  homeCatalogPreferencesRepositoryProvider.overrideWithValue(
                    repository,
                  ),
                ],
                child: const MaterialApp(
                  home: SearchScreen(isTelevision: true),
                ),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }, () => client),
        );
        expect(calls, ['disabled']);
        if (retire) await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          first.complete(<String>{});
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump(const Duration(milliseconds: 500));
        expect(calls, ['disabled', 'extras', 'order', 'hero']);
        if (!retire) {
          await tester.runAsync(() async {
            MainPageBridge.notifyHomeSettingsChanged();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump(const Duration(milliseconds: 500));
          expect(calls, [
            'disabled',
            'extras',
            'order',
            'hero',
            'disabled',
            'extras',
            'order',
            'hero',
          ]);
          await tester.pumpWidget(const SizedBox());
        }
        final count = calls.length;
        MainPageBridge.notifyHomeSettingsChanged();
        await tester.pump(const Duration(seconds: 2));
        expect(calls.length, count);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
